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
  primaryEmail: process.env.SUPABASE_TEST_EMAIL.trim(),
  primaryPassword: process.env.SUPABASE_TEST_PASSWORD,
  limit: 200
};

const runId = crypto.randomUUID();
const activityId = crypto.randomUUID();
const activityName = `contract-${Date.now()}`;
const sessionId = crypto.randomUUID();
const timerTemplateId = crypto.randomUUID();
const timerIntervalId = crypto.randomUUID();
const invalidTimerIntervalId = crypto.randomUUID();
const sessionItemId = crypto.randomUUID();
const climbEntryId = crypto.randomUUID();
const climbStyleId = crypto.randomUUID();
const climbGymId = crypto.randomUUID();
const runCursor = new Date(Date.now() - 60_000).toISOString();

const primarySession = await signInWithPassword({
  url: config.url,
  apikey: config.apikey,
  email: config.primaryEmail,
  password: config.primaryPassword
});

const authPreflightResponse = await rawSyncRequest({
  url: config.url,
  path: "push",
  token: primarySession.access_token,
  body: { deviceId: `contract-preflight-${runId}`, baseCursor: runCursor, mutations: [] }
});
assertSyncAuthPreflight(authPreflightResponse);

const unauthPushResponse = await rawSyncRequest({
  url: config.url,
  path: "push",
  body: { deviceId: `contract-no-auth-${runId}`, baseCursor: runCursor, mutations: [] }
});
assertStatus(unauthPushResponse, 401, "push_without_bearer");

const unauthPullResponse = await rawSyncRequest({
  url: config.url,
  path: "pull",
  body: { cursor: runCursor, limit: 1 }
});
assertStatus(unauthPullResponse, 401, "pull_without_bearer");

const invalidTokenPushResponse = await rawSyncRequest({
  url: config.url,
  path: "push",
  token: "invalid-bearer-token",
  body: { deviceId: `contract-invalid-auth-${runId}`, baseCursor: runCursor, mutations: [] }
});
assertStatus(invalidTokenPushResponse, 401, "push_with_invalid_bearer");

const invalidTokenPullResponse = await rawSyncRequest({
  url: config.url,
  path: "pull",
  token: "invalid-bearer-token",
  body: { cursor: runCursor, limit: 1 }
});
assertStatus(invalidTokenPullResponse, 401, "pull_with_invalid_bearer");

const createOpId = crypto.randomUUID();
const createResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: runCursor,
    mutations: [
      {
        opId: createOpId,
        entity: "activities",
        entityId: activityId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { name: activityName }
      }
    ]
  }
});
assertAcked(createResponse, createOpId, "create");

const replayResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: createResponse.newCursor,
    mutations: [
      {
        opId: createOpId,
        entity: "activities",
        entityId: activityId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { name: `${activityName}-replayed` }
      }
    ]
  }
});
assertAcked(replayResponse, createOpId, "idempotent_replay");
assertNoConflicts(replayResponse, "idempotent_replay");

const primaryAfterCreate = await pullUntilExhausted({
  url: config.url,
  token: primarySession.access_token,
  startCursor: runCursor,
  limit: config.limit
});

const createdDoc = findActivityDoc(primaryAfterCreate.changes, activityId);
if (!createdDoc) {
  throw new Error("Primary pull did not return newly created activity.");
}
if (createdDoc.name !== activityName) {
  throw new Error("Idempotent replay unexpectedly rewrote the activity payload.");
}

const noOpOpId = crypto.randomUUID();
const noOpResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: noOpOpId,
        entity: "activities",
        entityId: activityId,
        type: "upsert",
        baseVersion: Number(createdDoc.version ?? 1),
        updatedAtClient: new Date().toISOString(),
        payload: { name: activityName }
      }
    ]
  }
});
assertAcked(noOpResponse, noOpOpId, "no_op_upsert");
assertNoConflicts(noOpResponse, "no_op_upsert");

const afterNoOp = await pullUntilExhausted({
  url: config.url,
  token: primarySession.access_token,
  startCursor: primaryAfterCreate.lastCursor,
  limit: config.limit
});
const noOpActivityDoc = findActivityDoc(afterNoOp.changes, activityId);
if (noOpActivityDoc) {
  throw new Error("No-op upsert unexpectedly generated a pull change.");
}

const sessionCreateOpId = crypto.randomUUID();
const sessionCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: sessionCreateOpId,
        entity: "sessions",
        entityId: sessionId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { session_date: new Date().toISOString() }
      }
    ]
  }
});
assertAcked(sessionCreateResponse, sessionCreateOpId, "session_create");

const timerTemplateCreateOpId = crypto.randomUUID();
const timerTemplateCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: timerTemplateCreateOpId,
        entity: "timer_templates",
        entityId: timerTemplateId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          name: "Codex Contract Template",
          created_date: new Date().toISOString(),
          is_repeating: false,
          use_count: 0
        }
      }
    ]
  }
});
assertAcked(timerTemplateCreateResponse, timerTemplateCreateOpId, "timer_template_create");

const timerIntervalCreateOpId = crypto.randomUUID();
const timerIntervalCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: timerIntervalCreateOpId,
        entity: "timer_intervals",
        entityId: timerIntervalId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          timer_template_id: timerTemplateId,
          name: "Codex Contract Interval",
          work_time_seconds: 30,
          rest_time_seconds: 15,
          repetitions: 2
        }
      }
    ]
  }
});
assertAcked(timerIntervalCreateResponse, timerIntervalCreateOpId, "timer_interval_create");

const invalidTimerIntervalOpId = crypto.randomUUID();
const invalidTimerIntervalResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: invalidTimerIntervalOpId,
        entity: "timer_intervals",
        entityId: invalidTimerIntervalId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          timer_template_id: crypto.randomUUID(),
          name: "Codex Invalid Parent Interval",
          work_time_seconds: 20,
          rest_time_seconds: 10,
          repetitions: 1
        }
      }
    ]
  }
});
assertMutationFailed(invalidTimerIntervalResponse, invalidTimerIntervalOpId, "invalid_parent_reference", "timer_interval_invalid_parent");

const sessionItemCreateOpId = crypto.randomUUID();
const sessionItemCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: sessionItemCreateOpId,
        entity: "session_items",
        entityId: sessionItemId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          session_id: sessionId,
          exercise_name: "Contract Session Item",
          sort_order: 1
        }
      }
    ]
  }
});
assertAcked(sessionItemCreateResponse, sessionItemCreateOpId, "session_item_create");

const climbEntryCreateOpId = crypto.randomUUID();
const climbEntryCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: climbEntryCreateOpId,
        entity: "climb_entries",
        entityId: climbEntryId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          climb_type: "boulder",
          grade: "V4",
          style: "power",
          gym: "Codex Gym",
          date_logged: new Date().toISOString(),
          is_work_in_progress: false
        }
      }
    ]
  }
});
assertAcked(climbEntryCreateResponse, climbEntryCreateOpId, "climb_entry_create");

const climbStyleCreateOpId = crypto.randomUUID();
const climbStyleCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: climbStyleCreateOpId,
        entity: "climb_styles",
        entityId: climbStyleId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          name: "Contract Style",
          is_default: false
        }
      }
    ]
  }
});
assertAcked(climbStyleCreateResponse, climbStyleCreateOpId, "climb_style_create");

const climbGymCreateOpId = crypto.randomUUID();
const climbGymCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: climbGymCreateOpId,
        entity: "climb_gyms",
        entityId: climbGymId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          name: "Contract Gym",
          is_default: false
        }
      }
    ]
  }
});
assertAcked(climbGymCreateResponse, climbGymCreateOpId, "climb_gym_create");

const conflictOpId = crypto.randomUUID();
const conflictResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: conflictOpId,
        entity: "activities",
        entityId: activityId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { name: `${activityName}-conflict` }
      }
    ]
  }
});

const conflictMatched = (conflictResponse.conflicts ?? []).some(
  (conflict) =>
    conflict?.opId === conflictOpId &&
    conflict?.reason === "version_mismatch" &&
    Number(conflict?.serverVersion) >= 1
);
if (!conflictMatched) {
  throw new Error(`Expected version_mismatch conflict for op ${conflictOpId}.`);
}

const v2AfterCreate = await pullUntilExhausted({
  url: config.url,
  token: primarySession.access_token,
  startCursor: primaryAfterCreate.lastCursor,
  limit: config.limit
});

const sessionDoc = findEntityDoc(v2AfterCreate.changes, "sessions", sessionId);
if (!sessionDoc) {
  throw new Error("Session upsert verification failed.");
}

const timerTemplateDoc = findEntityDoc(v2AfterCreate.changes, "timer_templates", timerTemplateId);
if (!timerTemplateDoc) {
  throw new Error("Timer template upsert verification failed.");
}

const timerIntervalDoc = findEntityDoc(v2AfterCreate.changes, "timer_intervals", timerIntervalId);
if (!timerIntervalDoc) {
    throw new Error("Timer interval upsert verification failed.");
}

const sessionItemDoc = findEntityDoc(v2AfterCreate.changes, "session_items", sessionItemId);
if (!sessionItemDoc) {
    throw new Error("Session item upsert verification failed.");
}

const climbEntryDoc = findEntityDoc(v2AfterCreate.changes, "climb_entries", climbEntryId);
if (!climbEntryDoc) {
  throw new Error("Climb entry upsert verification failed.");
}

const climbStyleDoc = findEntityDoc(v2AfterCreate.changes, "climb_styles", climbStyleId);
if (!climbStyleDoc) {
    throw new Error("Climb style upsert verification failed.");
}

const climbGymDoc = findEntityDoc(v2AfterCreate.changes, "climb_gyms", climbGymId);
if (!climbGymDoc) {
    throw new Error("Climb gym upsert verification failed.");
}

const cleanupDeleteOp = crypto.randomUUID();
const cleanupResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: v2AfterCreate.lastCursor,
    mutations: [
      {
        opId: crypto.randomUUID(),
        entity: "climb_gyms",
        entityId: climbGymId,
        type: "delete",
        baseVersion: Number(climbGymDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "climb_styles",
        entityId: climbStyleId,
        type: "delete",
        baseVersion: Number(climbStyleDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "climb_entries",
        entityId: climbEntryId,
        type: "delete",
        baseVersion: Number(climbEntryDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "session_items",
        entityId: sessionItemId,
        type: "delete",
        baseVersion: Number(sessionItemDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "timer_intervals",
        entityId: timerIntervalId,
        type: "delete",
        baseVersion: Number(timerIntervalDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "timer_templates",
        entityId: timerTemplateId,
        type: "delete",
        baseVersion: Number(timerTemplateDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "sessions",
        entityId: sessionId,
        type: "delete",
        baseVersion: Number(sessionDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: cleanupDeleteOp,
        entity: "activities",
        entityId: activityId,
        type: "delete",
        baseVersion: Number(createdDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      }
    ]
  }
});
assertAcked(cleanupResponse, cleanupDeleteOp, "cleanup_delete");
assertNoConflicts(cleanupResponse, "cleanup_batch");

console.log(JSON.stringify({
  ok: true,
  runId,
  checks: {
    authEnforcement: true,
    idempotentReplay: true,
    noOpSuppression: true,
    versionConflict: true,
    v2EntityContract: true,
    parentValidation: true,
    cleanup: true
  },
  primaryEmail: config.primaryEmail
}, null, 2));

async function signInWithPassword({ url, apikey, email, password, allowFailure = false }) {
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
    if (allowFailure) {
      return null;
    }
    throw new Error(`Sign-in failed for ${email}: ${payload?.error_description || payload?.msg || response.status}`);
  }

  return { ...payload, email };
}


async function syncPush({ url, token, body }) {
  const response = await rawSyncRequest({ url, path: "push", token, body });
  if (!response.ok) {
    throw new Error(buildSyncRequestError(response, "push"));
  }

  return response.payload;
}

async function syncPull({ url, token, cursor, limit }) {
  const response = await rawSyncRequest({
    url,
    path: "pull",
    token,
    body: { cursor, limit }
  });
  if (!response.ok) {
    throw new Error(buildSyncRequestError(response, "pull"));
  }

  return response.payload;
}

async function rawSyncRequest({ url, path, body, token }) {
  const headers = {
    "content-type": "application/json"
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(`${url}/functions/v1/sync/${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body)
  });

  const payload = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, payload };
}

async function pullUntilExhausted({ url, token, startCursor, limit }) {
  let cursor = startCursor;
  let hasMore = true;
  const changes = [];

  while (hasMore) {
    const payload = await syncPull({ url, token, cursor, limit });
    changes.push(...(payload.changes || []));
    cursor = payload.nextCursor;
    hasMore = Boolean(payload.hasMore);
  }

  return {
    changes,
    lastCursor: cursor
  };
}

function assertAcked(payload, opId, label) {
  const acked = new Set(Array.isArray(payload.acknowledgedOpIds) ? payload.acknowledgedOpIds : []);
  if (!acked.has(opId)) {
    throw new Error(`${label} did not acknowledge opId ${opId}.`);
  }

  const failed = Array.isArray(payload.failed) ? payload.failed : [];
  if (failed.length > 0) {
    throw new Error(`${label} returned failures: ${JSON.stringify(failed)}`);
  }
}

function assertNoConflicts(payload, label) {
  const conflicts = Array.isArray(payload.conflicts) ? payload.conflicts : [];
  if (conflicts.length > 0) {
    throw new Error(`${label} returned conflicts: ${JSON.stringify(conflicts)}`);
  }
}

function assertMutationFailed(payload, opId, expectedReason, label) {
  const acked = new Set(Array.isArray(payload.acknowledgedOpIds) ? payload.acknowledgedOpIds : []);
  if (acked.has(opId)) {
    throw new Error(`${label} unexpectedly acknowledged opId ${opId}.`);
  }

  const failed = Array.isArray(payload.failed) ? payload.failed : [];
  const matchedFailed = failed.some((entry) => entry?.opId === opId && entry?.reason === expectedReason);
  if (!matchedFailed) {
    throw new Error(`${label} expected failed reason ${expectedReason}, received: ${JSON.stringify(payload)}`);
  }
}

function assertStatus(response, expectedStatus, label) {
  if (response.status !== expectedStatus) {
    throw new Error(`${label} expected status ${expectedStatus}, received ${response.status}.`);
  }
}

function assertSyncAuthPreflight(response) {
  if (response.ok) {
    return;
  }

  throw new Error(buildSyncRequestError(response, "sync auth preflight"));
}

function buildSyncRequestError(response, label) {
  if (isLikelyGatewayJwtMismatch(response)) {
    return `${label} failed (${response.status}): probable gateway JWT verification mismatch. Redeploy the sync function with verify_jwt=false for the current token flow.`;
  }

  return `${label} failed (${response.status}): ${describeSyncError(response.payload)}`;
}

function isLikelyGatewayJwtMismatch(response) {
  if (response.status !== 401) {
    return false;
  }

  return describeSyncError(response.payload).toLowerCase().includes("invalid jwt");
}

function describeSyncError(payload) {
  const fields = [payload?.error, payload?.message, payload?.msg, payload?.error_description]
    .filter((value) => typeof value === "string" && value.trim().length > 0);
  if (fields.length > 0) {
    return fields.join(" | ");
  }

  return "unknown_error";
}

function findActivityDoc(changes, activityId) {
  return findEntityDoc(changes, "activities", activityId);
}

function findEntityDoc(changes, entity, entityId) {
  for (const change of changes) {
    if (change.entity !== entity || change.type !== "upsert") {
      continue;
    }

    if (change.doc?.id === entityId) {
      return change.doc;
    }
  }

  return null;
}
