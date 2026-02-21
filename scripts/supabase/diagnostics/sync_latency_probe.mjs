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
  authSamples: Number(process.env.SUPABASE_LATENCY_AUTH_SAMPLES || 8),
  pullSamples: Number(process.env.SUPABASE_LATENCY_PULL_SAMPLES || 15),
  pullLimit: Number(process.env.SUPABASE_LATENCY_PULL_LIMIT || 50)
};

function elapsedMsFrom(startNanos) {
  return Number(process.hrtime.bigint() - startNanos) / 1e6;
}

function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const quantile = (q) => sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * q))];
  return {
    n: values.length,
    min_ms: Number(sorted[0].toFixed(1)),
    p50_ms: Number(quantile(0.5).toFixed(1)),
    p95_ms: Number(quantile(0.95).toFixed(1)),
    max_ms: Number(sorted[sorted.length - 1].toFixed(1)),
    avg_ms: Number((values.reduce((sum, current) => sum + current, 0) / values.length).toFixed(1))
  };
}

async function signInWithPassword() {
  const started = process.hrtime.bigint();
  const response = await fetch(`${config.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: config.apikey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ email: config.email, password: config.password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    throw new Error(`Auth failed: ${payload?.error_description || payload?.msg || response.status}`);
  }

  return {
    payload,
    elapsedMs: elapsedMsFrom(started)
  };
}

async function syncPush(token, body) {
  const started = process.hrtime.bigint();
  const response = await fetch(`${config.url}/functions/v1/sync/push`, {
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

  return {
    payload,
    elapsedMs: elapsedMsFrom(started)
  };
}

async function syncPull(token, cursor, limit) {
  const started = process.hrtime.bigint();
  const response = await fetch(`${config.url}/functions/v1/sync/pull`, {
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

  return {
    payload,
    elapsedMs: elapsedMsFrom(started)
  };
}

const authTimes = [];
for (let index = 0; index < config.authSamples; index += 1) {
  const auth = await signInWithPassword();
  authTimes.push(auth.elapsedMs);
}

const auth = await signInWithPassword();
const token = auth.payload.access_token;

const emptyPullCursor = new Date().toISOString();
const emptyPullTimes = [];
for (let index = 0; index < config.pullSamples; index += 1) {
  const pull = await syncPull(token, emptyPullCursor, config.pullLimit);
  emptyPullTimes.push(pull.elapsedMs);
}

const runId = Date.now();
const writeCursor = new Date(Date.now() - 60_000).toISOString();
const activityId = crypto.randomUUID();

const upsert = await syncPush(token, {
  deviceId: `latency-probe-${runId}`,
  baseCursor: writeCursor,
  mutations: [
    {
      opId: crypto.randomUUID(),
      entity: "activities",
      entityId: activityId,
      type: "upsert",
      baseVersion: 0,
      updatedAtClient: new Date().toISOString(),
      payload: {
        name: `latency-probe-${runId}`
      }
    }
  ]
});

const pullAfterUpsert = await syncPull(token, writeCursor, config.pullLimit);

const deleteMutation = await syncPush(token, {
  deviceId: `latency-probe-${runId}`,
  baseCursor: pullAfterUpsert.payload.nextCursor,
  mutations: [
    {
      opId: crypto.randomUUID(),
      entity: "activities",
      entityId: activityId,
      type: "delete",
      baseVersion: 1,
      updatedAtClient: new Date().toISOString()
    }
  ]
});

console.log(JSON.stringify({
  ok: true,
  config: {
    authSamples: config.authSamples,
    pullSamples: config.pullSamples,
    pullLimit: config.pullLimit
  },
  stats: {
    sign_in_password: summarize(authTimes),
    pull_empty_window: summarize(emptyPullTimes)
  },
  write_path: {
    upsert_push_ms: Number(upsert.elapsedMs.toFixed(1)),
    pull_after_upsert_ms: Number(pullAfterUpsert.elapsedMs.toFixed(1)),
    pull_after_upsert_changes: Array.isArray(pullAfterUpsert.payload?.changes) ? pullAfterUpsert.payload.changes.length : 0,
    delete_push_ms: Number(deleteMutation.elapsedMs.toFixed(1))
  }
}, null, 2));
