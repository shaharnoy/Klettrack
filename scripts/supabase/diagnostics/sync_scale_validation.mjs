#!/usr/bin/env node

const required = [
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_TEST_EMAIL",
  "SUPABASE_TEST_PASSWORD"
];

for (const key of required) {
  if (!process.env[key] || process.env[key].trim().length === 0) {
    console.error(`Missing env var: ${key}`);
    process.exit(1);
  }
}

const config = {
  url: process.env.SUPABASE_URL.trim().replace(/\/$/, ""),
  apikey: process.env.SUPABASE_PUBLISHABLE_KEY.trim(),
  email: process.env.SUPABASE_TEST_EMAIL.trim(),
  password: process.env.SUPABASE_TEST_PASSWORD,
  pageLimit: Number(process.env.SUPABASE_SCALE_PULL_LIMIT || 50),
  upsertCount: Number(process.env.SUPABASE_SCALE_UPSERT_COUNT || 120),
  fetchAttempts: Number(process.env.SUPABASE_SCALE_FETCH_ATTEMPTS || 4),
  noOpReplayCount: Number(process.env.SUPABASE_SCALE_NOOP_REPLAY_COUNT || 3),
  maxEntitySpanSeconds: Number(process.env.SUPABASE_SCALE_MAX_ENTITY_SPAN_SECONDS || 180),
  maxCycleDurationSeconds: Number(process.env.SUPABASE_SCALE_MAX_CYCLE_DURATION_SECONDS || 600),
  maxNetworkRetries: Number(process.env.SUPABASE_SCALE_MAX_NETWORK_RETRIES || 25),
  maxUnchangedRowVersionBumps: Number(process.env.SUPABASE_SCALE_MAX_UNCHANGED_ROW_VERSION_BUMPS || 0)
};

const startedAtMs = Date.now();
let networkRetries = 0;

const runTag = `scale-${Date.now()}`;
const runCursor = new Date(Date.now() - 60_000).toISOString();

const sessionId = crypto.randomUUID();
const timerTemplateId = crypto.randomUUID();

const sessionItems = Array.from({ length: config.upsertCount }, (_, index) => ({
  id: crypto.randomUUID(),
  exercise_name: `${runTag}-exercise-${index + 1}`,
  sort_order: index
}));

const timerIntervals = Array.from({ length: config.upsertCount }, (_, index) => ({
  id: crypto.randomUUID(),
  name: `${runTag}-interval-${index + 1}`,
  work_time_seconds: ((index % 6) + 1) * 5,
  rest_time_seconds: ((index % 3) + 1) * 3,
  repetitions: (index % 4) + 1
}));

const climbEntries = Array.from({ length: config.upsertCount }, (_, index) => ({
  id: crypto.randomUUID(),
  grade: `V${(index % 8) + 1}`,
  gym: `Scale Gym ${(index % 4) + 1}`
}));

const auth = await signInWithPassword(config);
const token = auth.access_token;

const parentUpsertResponse = await syncPush({
  url: config.url,
  token,
  body: {
    deviceId: `scale-${runTag}`,
    baseCursor: runCursor,
    mutations: [
      {
        opId: crypto.randomUUID(),
        entity: "sessions",
        entityId: sessionId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { session_date: new Date().toISOString() }
      },
      {
        opId: crypto.randomUUID(),
        entity: "timer_templates",
        entityId: timerTemplateId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          name: `Scale Template ${runTag}`,
          created_date: new Date().toISOString(),
          is_repeating: false,
          use_count: 0
        }
      }
    ]
  }
});
assertNoFailuresOrConflicts(parentUpsertResponse, "parent_upsert");

const sessionItemBatches = chunk(sessionItems, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: runCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "session_items",
    entityId: record.id,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      session_id: sessionId,
      exercise_name: record.exercise_name,
      sort_order: record.sort_order
    }
  }))
}));

const timerIntervalBatches = chunk(timerIntervals, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: runCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "timer_intervals",
    entityId: record.id,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      timer_template_id: timerTemplateId,
      name: record.name,
      work_time_seconds: record.work_time_seconds,
      rest_time_seconds: record.rest_time_seconds,
      repetitions: record.repetitions
    }
  }))
}));

const climbEntryBatches = chunk(climbEntries, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: runCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "climb_entries",
    entityId: record.id,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      climb_type: "boulder",
      grade: record.grade,
      style: "power",
      gym: record.gym,
      date_logged: new Date().toISOString(),
      is_work_in_progress: false
    }
  }))
}));

for (const body of [...sessionItemBatches, ...timerIntervalBatches, ...climbEntryBatches]) {
  const response = await syncPush({ url: config.url, token, body });
  assertNoFailuresOrConflicts(response, "upsert");
}

const afterUpsert = await pullUntilExhausted({
  url: config.url,
  token,
  startCursor: runCursor,
  limit: config.pageLimit
});

const matchedSessionItems = sessionItems.filter((record) =>
  afterUpsert.changes.some((change) => change?.entity === "session_items" && change?.type === "upsert" && change?.doc?.id === record.id)
);
if (matchedSessionItems.length !== sessionItems.length) {
  throw new Error(`Expected ${sessionItems.length} session_items upserts in pull, got ${matchedSessionItems.length}.`);
}

const matchedTimerIntervals = timerIntervals.filter((record) =>
  afterUpsert.changes.some((change) => change?.entity === "timer_intervals" && change?.type === "upsert" && change?.doc?.id === record.id)
);
if (matchedTimerIntervals.length !== timerIntervals.length) {
  throw new Error(`Expected ${timerIntervals.length} timer_intervals upserts in pull, got ${matchedTimerIntervals.length}.`);
}

const matchedClimbEntries = climbEntries.filter((record) =>
  afterUpsert.changes.some((change) => change?.entity === "climb_entries" && change?.type === "upsert" && change?.doc?.id === record.id)
);
if (matchedClimbEntries.length !== climbEntries.length) {
  throw new Error(`Expected ${climbEntries.length} climb_entries upserts in pull, got ${matchedClimbEntries.length}.`);
}

const spanByEntity = {
  session_items: collectSpanSeconds(afterUpsert.changes, "session_items", sessionItems.map((record) => record.id)),
  timer_intervals: collectSpanSeconds(afterUpsert.changes, "timer_intervals", timerIntervals.map((record) => record.id)),
  climb_entries: collectSpanSeconds(afterUpsert.changes, "climb_entries", climbEntries.map((record) => record.id))
};

assertSpanThreshold(spanByEntity.session_items, "session_items", config.maxEntitySpanSeconds);
assertSpanThreshold(spanByEntity.timer_intervals, "timer_intervals", config.maxEntitySpanSeconds);
assertSpanThreshold(spanByEntity.climb_entries, "climb_entries", config.maxEntitySpanSeconds);

const versionsByEntityAndId = new Map();
for (const change of afterUpsert.changes) {
  if (change?.type !== "upsert" || !change?.entity || !change?.doc?.id) {
    continue;
  }
  versionsByEntityAndId.set(`${change.entity}:${change.doc.id}`, Number(change.doc.version || 1));
}

const sessionItemDeleteBatches = chunk(sessionItems, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: afterUpsert.lastCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "session_items",
    entityId: record.id,
    type: "delete",
    baseVersion: versionsByEntityAndId.get(`session_items:${record.id}`) || 1,
    updatedAtClient: new Date().toISOString()
  }))
}));

const timerIntervalDeleteBatches = chunk(timerIntervals, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: afterUpsert.lastCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "timer_intervals",
    entityId: record.id,
    type: "delete",
    baseVersion: versionsByEntityAndId.get(`timer_intervals:${record.id}`) || 1,
    updatedAtClient: new Date().toISOString()
  }))
}));

const climbEntryDeleteBatches = chunk(climbEntries, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: afterUpsert.lastCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "climb_entries",
    entityId: record.id,
    type: "delete",
    baseVersion: versionsByEntityAndId.get(`climb_entries:${record.id}`) || 1,
    updatedAtClient: new Date().toISOString()
  }))
}));

for (const body of [...sessionItemDeleteBatches, ...timerIntervalDeleteBatches, ...climbEntryDeleteBatches]) {
  const response = await syncPush({ url: config.url, token, body });
  assertNoFailuresOrConflicts(response, "delete");
}

const parentDeleteResponse = await syncPush({
  url: config.url,
  token,
  body: {
    deviceId: `scale-${runTag}`,
    baseCursor: afterUpsert.lastCursor,
    mutations: [
      {
        opId: crypto.randomUUID(),
        entity: "timer_templates",
        entityId: timerTemplateId,
        type: "delete",
        baseVersion: versionsByEntityAndId.get(`timer_templates:${timerTemplateId}`) || 1,
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "sessions",
        entityId: sessionId,
        type: "delete",
        baseVersion: versionsByEntityAndId.get(`sessions:${sessionId}`) || 1,
        updatedAtClient: new Date().toISOString()
      }
    ]
  }
});
assertNoFailuresOrConflicts(parentDeleteResponse, "parent_delete");

const afterDelete = await pullUntilExhausted({
  url: config.url,
  token,
  startCursor: afterUpsert.lastCursor,
  limit: config.pageLimit
});

const deletedSessionItems = sessionItems.filter((record) =>
  afterDelete.changes.some((change) => change?.entity === "session_items" && change?.type === "delete" && change?.entityId === record.id)
);
if (deletedSessionItems.length !== sessionItems.length) {
  throw new Error(`Expected ${sessionItems.length} session_items tombstones, got ${deletedSessionItems.length}.`);
}

const deletedTimerIntervals = timerIntervals.filter((record) =>
  afterDelete.changes.some((change) => change?.entity === "timer_intervals" && change?.type === "delete" && change?.entityId === record.id)
);
if (deletedTimerIntervals.length !== timerIntervals.length) {
  throw new Error(`Expected ${timerIntervals.length} timer_intervals tombstones, got ${deletedTimerIntervals.length}.`);
}

const deletedClimbEntries = climbEntries.filter((record) =>
  afterDelete.changes.some((change) => change?.entity === "climb_entries" && change?.type === "delete" && change?.entityId === record.id)
);
if (deletedClimbEntries.length !== climbEntries.length) {
  throw new Error(`Expected ${climbEntries.length} climb_entries tombstones, got ${deletedClimbEntries.length}.`);
}

const noOpProbeResult = await runNoOpProbe({ token, startCursor: afterDelete.lastCursor, runTag });
if (noOpProbeResult.versionBumps > config.maxUnchangedRowVersionBumps) {
  throw new Error(
    `No-op unchanged-row version bumps exceeded threshold: ${noOpProbeResult.versionBumps} > ${config.maxUnchangedRowVersionBumps}.`
  );
}

const cycleDurationSeconds = Number(((Date.now() - startedAtMs) / 1000).toFixed(1));
if (cycleDurationSeconds > config.maxCycleDurationSeconds) {
  throw new Error(`Cycle duration exceeded threshold: ${cycleDurationSeconds}s > ${config.maxCycleDurationSeconds}s.`);
}
if (networkRetries > config.maxNetworkRetries) {
  throw new Error(`Network retries exceeded threshold: ${networkRetries} > ${config.maxNetworkRetries}.`);
}

console.log(JSON.stringify({
  ok: true,
  runTag,
  checkedRecords: {
    session_items: sessionItems.length,
    timer_intervals: timerIntervals.length,
    climb_entries: climbEntries.length
  },
  pullPages: {
    afterUpsert: afterUpsert.pageCount,
    afterDelete: afterDelete.pageCount
  },
  spansSeconds: spanByEntity,
  noOpProbe: noOpProbeResult,
  diagnostics: {
    cycleDurationSeconds,
    networkRetries
  },
  thresholds: {
    maxEntitySpanSeconds: config.maxEntitySpanSeconds,
    maxCycleDurationSeconds: config.maxCycleDurationSeconds,
    maxNetworkRetries: config.maxNetworkRetries,
    maxUnchangedRowVersionBumps: config.maxUnchangedRowVersionBumps
  },
  checks: {
    sessionItemsUpsertsPulled: true,
    timerIntervalsUpsertsPulled: true,
    climbEntriesUpsertsPulled: true,
    sessionItemsDeletesPulled: true,
    timerIntervalsDeletesPulled: true,
    climbEntriesDeletesPulled: true,
    paginationExercised: afterUpsert.pageCount > 1 || afterDelete.pageCount > 1,
    spanThresholdRespected: true,
    cycleDurationThresholdRespected: true,
    retryThresholdRespected: true,
    unchangedRowNoOpThresholdRespected: true
  }
}, null, 2));

function chunk(values, size) {
  const output = [];
  for (let index = 0; index < values.length; index += size) {
    output.push(values.slice(index, index + size));
  }
  return output;
}

function collectSpanSeconds(changes, entity, ids) {
  const idSet = new Set(ids);
  const rows = changes.filter(
    (change) => change?.entity === entity && change?.type === "upsert" && idSet.has(change?.doc?.id)
  );

  const createdAtValues = rows
    .map((change) => Date.parse(change?.doc?.created_at))
    .filter((value) => Number.isFinite(value));
  const updatedAtServerValues = rows
    .map((change) => Date.parse(change?.doc?.updated_at_server))
    .filter((value) => Number.isFinite(value));

  return {
    created: spanInSeconds(createdAtValues),
    updated_server: spanInSeconds(updatedAtServerValues)
  };
}

function spanInSeconds(values) {
  if (values.length <= 1) {
    return 0;
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  return Number(((max - min) / 1000).toFixed(3));
}

function assertSpanThreshold(spanMetrics, entity, thresholdSeconds) {
  if (spanMetrics.created > thresholdSeconds) {
    throw new Error(
      `${entity} created_at span exceeded threshold: ${spanMetrics.created}s > ${thresholdSeconds}s.`
    );
  }
  if (spanMetrics.updated_server > thresholdSeconds) {
    throw new Error(
      `${entity} updated_at_server span exceeded threshold: ${spanMetrics.updated_server}s > ${thresholdSeconds}s.`
    );
  }
}

async function runNoOpProbe({ token, startCursor, runTag }) {
  const activityId = crypto.randomUUID();
  const baseName = `${runTag}-noop-probe`;

  await syncPush({
    url: config.url,
    token,
    body: {
      deviceId: `scale-noop-${runTag}`,
      baseCursor: startCursor,
      mutations: [
        {
          opId: crypto.randomUUID(),
          entity: "activities",
          entityId: activityId,
          type: "upsert",
          baseVersion: 0,
          updatedAtClient: new Date().toISOString(),
          payload: { name: baseName }
        }
      ]
    }
  });

  const afterCreate = await pullUntilExhausted({
    url: config.url,
    token,
    startCursor,
    limit: config.pageLimit
  });
  const createdDoc = afterCreate.changes.find(
    (change) => change?.entity === "activities" && change?.type === "upsert" && change?.doc?.id === activityId
  )?.doc;

  if (!createdDoc) {
    throw new Error("No-op probe failed: create pull change missing.");
  }

  const createdVersion = Number(createdDoc.version || 1);

  for (let index = 0; index < config.noOpReplayCount; index += 1) {
    const replay = await syncPush({
      url: config.url,
      token,
      body: {
        deviceId: `scale-noop-${runTag}`,
        baseCursor: afterCreate.lastCursor,
        mutations: [
          {
            opId: crypto.randomUUID(),
            entity: "activities",
            entityId: activityId,
            type: "upsert",
            baseVersion: createdVersion,
            updatedAtClient: new Date().toISOString(),
            payload: { name: baseName }
          }
        ]
      }
    });
    assertNoFailuresOrConflicts(replay, "noop_replay");
  }

  const afterReplay = await pullUntilExhausted({
    url: config.url,
    token,
    startCursor: afterCreate.lastCursor,
    limit: config.pageLimit
  });

  const replayChanges = afterReplay.changes.filter(
    (change) => change?.entity === "activities" && change?.type === "upsert" && change?.doc?.id === activityId
  );

  const finalVersion = replayChanges.length > 0
    ? Number(replayChanges.at(-1)?.doc?.version || createdVersion)
    : createdVersion;

  const versionBumps = Math.max(0, finalVersion - createdVersion);

  await syncPush({
    url: config.url,
    token,
    body: {
      deviceId: `scale-noop-${runTag}`,
      baseCursor: afterReplay.lastCursor,
      mutations: [
        {
          opId: crypto.randomUUID(),
          entity: "activities",
          entityId: activityId,
          type: "delete",
          baseVersion: finalVersion,
          updatedAtClient: new Date().toISOString()
        }
      ]
    }
  });

  return {
    noOpReplayCount: config.noOpReplayCount,
    replayPullChanges: replayChanges.length,
    createdVersion,
    finalVersion,
    versionBumps
  };
}

async function signInWithPassword({ url, apikey, email, password }) {
  const response = await fetchWithRetry(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ email, password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    throw new Error(`Auth failed: ${payload?.error_description || payload?.msg || response.status}`);
  }

  return payload;
}

async function syncPush({ url, token, body }) {
  const response = await fetchWithRetry(`${url}/functions/v1/sync/push`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Push failed (${response.status}): ${payload?.error || "unknown_error"}`);
  }

  return payload;
}

async function syncPull({ url, token, cursor, limit }) {
  const response = await fetchWithRetry(`${url}/functions/v1/sync/pull`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ cursor, limit })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Pull failed (${response.status}): ${payload?.error || "unknown_error"}`);
  }

  return payload;
}

async function pullUntilExhausted({ url, token, startCursor, limit }) {
  let cursor = startCursor;
  let hasMore = true;
  let pageCount = 0;
  const changes = [];
  const upperBoundPages = 400;

  while (hasMore && pageCount < upperBoundPages) {
    const payload = await syncPull({ url, token, cursor, limit });
    const pageChanges = Array.isArray(payload.changes) ? payload.changes : [];
    changes.push(...pageChanges);
    cursor = payload.nextCursor;
    hasMore = Boolean(payload.hasMore);
    pageCount += 1;
  }

  return {
    changes,
    lastCursor: cursor,
    pageCount
  };
}

async function fetchWithRetry(url, init) {
  let lastError = null;
  const attempts = Math.max(1, config.fetchAttempts);

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await fetch(url, init);
    } catch (error) {
      lastError = error;
      if (attempt === attempts - 1) {
        break;
      }
      networkRetries += 1;
      await sleep((attempt + 1) * 250);
    }
  }

  throw lastError || new Error("fetchWithRetry failed");
}

async function sleep(delayMs) {
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}

function assertNoFailuresOrConflicts(response, label) {
  const failed = Array.isArray(response.failed) ? response.failed : [];
  const conflicts = Array.isArray(response.conflicts) ? response.conflicts : [];

  if (failed.length > 0) {
    throw new Error(`${label} push returned failed mutations: ${JSON.stringify(failed)}`);
  }
  if (conflicts.length > 0) {
    throw new Error(`${label} push returned conflicts: ${JSON.stringify(conflicts)}`);
  }
}
