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
const seededActivityID = crypto.randomUUID();
const seededActivityName = `hydration-smoke-${Date.now()}`;
const runCursor = new Date(Date.now() - 60_000).toISOString();

const auth = await signInWithPassword(config);
const token = auth.access_token;

const seedOp = crypto.randomUUID();
const seedPush = await syncPush({
  url: config.url,
  token,
  body: {
    deviceId: `web-hydration-${runId}`,
    baseCursor: runCursor,
    mutations: [
      {
        opId: seedOp,
        entity: "activities",
        entityId: seededActivityID,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: { name: seededActivityName }
      }
    ]
  }
});
assertPushAccepted(seedPush, seedOp, "seed_upsert");

const hydrated = await pullUntilExhausted({
  url: config.url,
  token,
  startCursor: runCursor,
  limit: config.limit
});

const foundSeed = hydrated.changes.some(
  (change) =>
    change.entity === "activities" &&
    change.type === "upsert" &&
    change.doc?.id === seededActivityID
);

if (!foundSeed) {
  throw new Error("Hydration smoke failed: seeded activity not present in pull hydration changes.");
}

const cleanupOp = crypto.randomUUID();
const cleanupPush = await syncPush({
  url: config.url,
  token,
  body: {
    deviceId: `web-hydration-${runId}`,
    baseCursor: hydrated.lastCursor,
    mutations: [
      {
        opId: cleanupOp,
        entity: "activities",
        entityId: seededActivityID,
        type: "delete",
        baseVersion: Number(findVersion(hydrated.changes, seededActivityID) || 0),
        updatedAtClient: new Date().toISOString()
      }
    ]
  }
});
assertPushAccepted(cleanupPush, cleanupOp, "cleanup_delete");

console.log(JSON.stringify({
  ok: true,
  email: config.email,
  checks: {
    signedIn: true,
    seedAcked: true,
    hydrationPulled: true,
    cleanupAcked: true
  }
}, null, 2));

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

async function fetchWithRetry(url, init, attempts = 4) {
  let lastError = null;
  for (let index = 0; index < attempts; index += 1) {
    try {
      return await fetch(url, init);
    } catch (error) {
      lastError = error;
      const delayMs = (index + 1) * 200;
      await sleep(delayMs);
    }
  }
  throw lastError || new Error("fetchWithRetry failed");
}

async function sleep(delayMs) {
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}

function findVersion(changes, entityId) {
  for (const change of changes) {
    if (change.entity === "activities" && change.type === "upsert" && change.doc?.id === entityId) {
      return change.doc.version;
    }
  }
  return null;
}
