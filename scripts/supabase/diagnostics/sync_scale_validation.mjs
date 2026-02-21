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
  pageLimit: 50,
  upsertCount: Number(process.env.SUPABASE_SCALE_UPSERT_COUNT || 120)
};

const runTag = `scale-${Date.now()}`;
const runCursor = new Date(Date.now() - 60_000).toISOString();

const sessionId = crypto.randomUUID();
const timerTemplateId = crypto.randomUUID();
const timerSessionId = crypto.randomUUID();

const sessionItems = Array.from({ length: config.upsertCount }, (_, index) => ({
  id: crypto.randomUUID(),
  exercise_name: `${runTag}-exercise-${index + 1}`,
  sort_order: index
}));

const timerLaps = Array.from({ length: config.upsertCount }, (_, index) => ({
  id: crypto.randomUUID(),
  lap_number: index + 1,
  elapsed_seconds: (index + 1) * 5
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
      },
      {
        opId: crypto.randomUUID(),
        entity: "timer_sessions",
        entityId: timerSessionId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          start_date: new Date().toISOString(),
          timer_template_id: timerTemplateId,
          total_elapsed_seconds: 0,
          completed_intervals: 0,
          was_completed: false
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

const timerLapBatches = chunk(timerLaps, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: runCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "timer_laps",
    entityId: record.id,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      timer_session_id: timerSessionId,
      lap_number: record.lap_number,
      timestamp: new Date().toISOString(),
      elapsed_seconds: record.elapsed_seconds
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

for (const body of [...sessionItemBatches, ...timerLapBatches, ...climbEntryBatches]) {
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

const matchedTimerLaps = timerLaps.filter((record) =>
  afterUpsert.changes.some((change) => change?.entity === "timer_laps" && change?.type === "upsert" && change?.doc?.id === record.id)
);
if (matchedTimerLaps.length !== timerLaps.length) {
  throw new Error(`Expected ${timerLaps.length} timer_laps upserts in pull, got ${matchedTimerLaps.length}.`);
}

const matchedClimbEntries = climbEntries.filter((record) =>
  afterUpsert.changes.some((change) => change?.entity === "climb_entries" && change?.type === "upsert" && change?.doc?.id === record.id)
);
if (matchedClimbEntries.length !== climbEntries.length) {
  throw new Error(`Expected ${climbEntries.length} climb_entries upserts in pull, got ${matchedClimbEntries.length}.`);
}

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

const timerLapDeleteBatches = chunk(timerLaps, 100).map((group) => ({
  deviceId: `scale-${runTag}`,
  baseCursor: afterUpsert.lastCursor,
  mutations: group.map((record) => ({
    opId: crypto.randomUUID(),
    entity: "timer_laps",
    entityId: record.id,
    type: "delete",
    baseVersion: versionsByEntityAndId.get(`timer_laps:${record.id}`) || 1,
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

for (const body of [...sessionItemDeleteBatches, ...timerLapDeleteBatches, ...climbEntryDeleteBatches]) {
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
        entity: "timer_sessions",
        entityId: timerSessionId,
        type: "delete",
        baseVersion: versionsByEntityAndId.get(`timer_sessions:${timerSessionId}`) || 1,
        updatedAtClient: new Date().toISOString()
      },
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

const deletedTimerLaps = timerLaps.filter((record) =>
  afterDelete.changes.some((change) => change?.entity === "timer_laps" && change?.type === "delete" && change?.entityId === record.id)
);
if (deletedTimerLaps.length !== timerLaps.length) {
  throw new Error(`Expected ${timerLaps.length} timer_laps tombstones, got ${deletedTimerLaps.length}.`);
}

const deletedClimbEntries = climbEntries.filter((record) =>
  afterDelete.changes.some((change) => change?.entity === "climb_entries" && change?.type === "delete" && change?.entityId === record.id)
);
if (deletedClimbEntries.length !== climbEntries.length) {
  throw new Error(`Expected ${climbEntries.length} climb_entries tombstones, got ${deletedClimbEntries.length}.`);
}

console.log(JSON.stringify({
  ok: true,
  runTag,
  checkedRecords: {
    session_items: sessionItems.length,
    timer_laps: timerLaps.length,
    climb_entries: climbEntries.length
  },
  pullPages: {
    afterUpsert: afterUpsert.pageCount,
    afterDelete: afterDelete.pageCount
  },
  checks: {
    sessionItemsUpsertsPulled: true,
    timerLapsUpsertsPulled: true,
    climbEntriesUpsertsPulled: true,
    sessionItemsDeletesPulled: true,
    timerLapsDeletesPulled: true,
    climbEntriesDeletesPulled: true,
    paginationExercised: afterUpsert.pageCount > 1 || afterDelete.pageCount > 1
  }
}, null, 2));

function chunk(values, size) {
  const output = [];
  for (let index = 0; index < values.length; index += size) {
    output.push(values.slice(index, index + size));
  }
  return output;
}

async function signInWithPassword({ url, apikey, email, password }) {
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
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
  const response = await fetch(`${url}/functions/v1/sync/push`, {
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
  const response = await fetch(`${url}/functions/v1/sync/pull`, {
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
