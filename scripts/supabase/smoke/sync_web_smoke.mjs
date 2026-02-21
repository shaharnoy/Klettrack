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
  limit: 200
};

const runId = crypto.randomUUID();
const activityId = crypto.randomUUID();
const activityName = `codex-smoke-${Date.now()}`;
const runCursor = new Date(Date.now() - 60_000).toISOString();

const auth = await signInWithPassword(config);
const accessToken = auth.access_token;

const upsertOp = crypto.randomUUID();
const upsertResponse = await syncPush({
  url: config.url,
  token: accessToken,
  body: {
    deviceId: `web-smoke-${runId}`,
    baseCursor: runCursor,
    mutations: [
      {
        opId: upsertOp,
        entity: "activities",
        entityId: activityId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          name: activityName
        }
      }
    ]
  }
});
assertPushAccepted(upsertResponse, upsertOp, "upsert");

const afterUpsert = await pullUntilExhausted({
  url: config.url,
  token: accessToken,
  startCursor: runCursor,
  limit: config.limit
});

const createdDoc = findActivityDoc(afterUpsert.changes, activityId);
if (!createdDoc) {
  throw new Error("Upsert verification failed: created activity not found in pull changes.");
}

const deleteOp = crypto.randomUUID();
const deleteResponse = await syncPush({
  url: config.url,
  token: accessToken,
  body: {
    deviceId: `web-smoke-${runId}`,
    baseCursor: afterUpsert.lastCursor,
    mutations: [
      {
        opId: deleteOp,
        entity: "activities",
        entityId: activityId,
        type: "delete",
        baseVersion: Number(createdDoc.version || 0),
        updatedAtClient: new Date().toISOString()
      }
    ]
  }
});
assertPushAccepted(deleteResponse, deleteOp, "delete");

const afterDelete = await pullUntilExhausted({
  url: config.url,
  token: accessToken,
  startCursor: afterUpsert.lastCursor,
  limit: config.limit
});

const deleteFound = afterDelete.changes.some((change) =>
  change.entity === "activities" &&
  change.type === "delete" &&
  change.entityId === activityId
);

if (!deleteFound) {
  throw new Error("Delete verification failed: tombstone not found in pull changes.");
}

console.log(JSON.stringify({
  ok: true,
  email: config.email,
  activityId,
  activityName,
  checks: {
    signedIn: true,
    upsertAcked: true,
    upsertPulled: true,
    deleteAcked: true,
    deletePulled: true
  }
}, null, 2));

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

function assertPushAccepted(payload, opId, label) {
  const failed = Array.isArray(payload.failed) ? payload.failed : [];
  const conflicts = Array.isArray(payload.conflicts) ? payload.conflicts : [];
  const acked = new Set(Array.isArray(payload.acknowledgedOpIds) ? payload.acknowledgedOpIds : []);

  if (failed.length > 0) {
    throw new Error(`${label} push returned failed: ${JSON.stringify(failed)}`);
  }
  if (conflicts.length > 0) {
    throw new Error(`${label} push returned conflicts: ${JSON.stringify(conflicts)}`);
  }
  if (!acked.has(opId)) {
    throw new Error(`${label} push did not acknowledge opId ${opId}`);
  }
}

function findActivityDoc(changes, activityId) {
  for (const change of changes) {
    if (change.entity !== "activities" || change.type !== "upsert") {
      continue;
    }

    const doc = change.doc;
    if (doc?.id === activityId) {
      return doc;
    }
  }

  return null;
}
