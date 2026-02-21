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
const timestamp = Date.now();
const runCursor = new Date(Date.now() - 60_000).toISOString();

const ids = {
  dayType: crypto.randomUUID(),
  style: crypto.randomUUID(),
  gym: crypto.randomUUID(),
  timerTemplate: crypto.randomUUID()
};

const names = {
  dayTypeCreate: `codex-day-${timestamp}`,
  dayTypeUpdate: `codex-day-updated-${timestamp}`,
  styleCreate: `codex-style-${timestamp}`,
  styleUpdate: `codex-style-updated-${timestamp}`,
  gymCreate: `codex-gym-${timestamp}`,
  gymUpdate: `codex-gym-updated-${timestamp}`,
  timerCreate: `codex-template-${timestamp}`,
  timerUpdate: `codex-template-updated-${timestamp}`
};

const auth = await signInWithPassword(config);
const accessToken = auth.access_token;

const createMutations = [
  {
    opId: crypto.randomUUID(),
    entity: "day_types",
    entityId: ids.dayType,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      key: `codex-${timestamp}`,
      name: names.dayTypeCreate,
      color_key: "gray",
      display_order: 9000,
      is_default: false,
      is_hidden: false
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_styles",
    entityId: ids.style,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.styleCreate,
      is_default: false,
      is_hidden: false
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_gyms",
    entityId: ids.gym,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.gymCreate,
      is_default: false
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "timer_templates",
    entityId: ids.timerTemplate,
    type: "upsert",
    baseVersion: 0,
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.timerCreate,
      template_description: "Data manager smoke test template",
      total_time_seconds: 120,
      is_repeating: false,
      repeat_count: null,
      rest_time_between_intervals: null,
      created_date: new Date().toISOString(),
      last_used_date: null,
      use_count: 0
    }
  }
];

const createResponse = await syncPush({
  url: config.url,
  token: accessToken,
  body: {
    deviceId: `web-data-manager-smoke-${runId}`,
    baseCursor: runCursor,
    mutations: createMutations
  }
});
assertPushAccepted(createResponse, createMutations.map((mutation) => mutation.opId), "create");

const afterCreate = await pullUntilExhausted({
  url: config.url,
  token: accessToken,
  startCursor: runCursor,
  limit: config.limit
});

const createdDocs = {
  dayType: findEntityDoc(afterCreate.changes, "day_types", ids.dayType),
  style: findEntityDoc(afterCreate.changes, "climb_styles", ids.style),
  gym: findEntityDoc(afterCreate.changes, "climb_gyms", ids.gym),
  timerTemplate: findEntityDoc(afterCreate.changes, "timer_templates", ids.timerTemplate)
};
assertDoc(createdDocs.dayType, "day_types create");
assertDoc(createdDocs.style, "climb_styles create");
assertDoc(createdDocs.gym, "climb_gyms create");
assertDoc(createdDocs.timerTemplate, "timer_templates create");

const updateMutations = [
  {
    opId: crypto.randomUUID(),
    entity: "day_types",
    entityId: ids.dayType,
    type: "upsert",
    baseVersion: Number(createdDocs.dayType.version || 0),
    updatedAtClient: new Date().toISOString(),
    payload: {
      key: createdDocs.dayType.key,
      name: names.dayTypeUpdate,
      color_key: createdDocs.dayType.color_key || "gray",
      display_order: Number(createdDocs.dayType.display_order || 9000),
      is_default: Boolean(createdDocs.dayType.is_default),
      is_hidden: Boolean(createdDocs.dayType.is_hidden)
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_styles",
    entityId: ids.style,
    type: "upsert",
    baseVersion: Number(createdDocs.style.version || 0),
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.styleUpdate,
      is_default: Boolean(createdDocs.style.is_default),
      is_hidden: Boolean(createdDocs.style.is_hidden)
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_gyms",
    entityId: ids.gym,
    type: "upsert",
    baseVersion: Number(createdDocs.gym.version || 0),
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.gymUpdate,
      is_default: Boolean(createdDocs.gym.is_default)
    }
  },
  {
    opId: crypto.randomUUID(),
    entity: "timer_templates",
    entityId: ids.timerTemplate,
    type: "upsert",
    baseVersion: Number(createdDocs.timerTemplate.version || 0),
    updatedAtClient: new Date().toISOString(),
    payload: {
      name: names.timerUpdate,
      template_description: "Updated by data manager smoke test",
      total_time_seconds: Number(createdDocs.timerTemplate.total_time_seconds || 120),
      is_repeating: Boolean(createdDocs.timerTemplate.is_repeating),
      repeat_count: createdDocs.timerTemplate.repeat_count ?? null,
      rest_time_between_intervals: createdDocs.timerTemplate.rest_time_between_intervals ?? null,
      created_date: createdDocs.timerTemplate.created_date,
      last_used_date: createdDocs.timerTemplate.last_used_date ?? null,
      use_count: Number(createdDocs.timerTemplate.use_count || 0)
    }
  }
];

const updateResponse = await syncPush({
  url: config.url,
  token: accessToken,
  body: {
    deviceId: `web-data-manager-smoke-${runId}`,
    baseCursor: afterCreate.lastCursor,
    mutations: updateMutations
  }
});
assertPushAccepted(updateResponse, updateMutations.map((mutation) => mutation.opId), "update");

const afterUpdate = await pullUntilExhausted({
  url: config.url,
  token: accessToken,
  startCursor: afterCreate.lastCursor,
  limit: config.limit
});

const updatedDocs = {
  dayType: findEntityDoc(afterUpdate.changes, "day_types", ids.dayType),
  style: findEntityDoc(afterUpdate.changes, "climb_styles", ids.style),
  gym: findEntityDoc(afterUpdate.changes, "climb_gyms", ids.gym),
  timerTemplate: findEntityDoc(afterUpdate.changes, "timer_templates", ids.timerTemplate)
};
assertDoc(updatedDocs.dayType, "day_types update");
assertDoc(updatedDocs.style, "climb_styles update");
assertDoc(updatedDocs.gym, "climb_gyms update");
assertDoc(updatedDocs.timerTemplate, "timer_templates update");

if (updatedDocs.dayType.name !== names.dayTypeUpdate) {
  throw new Error(`day_types update verification failed. Expected "${names.dayTypeUpdate}", got "${updatedDocs.dayType.name || ""}".`);
}

const deleteMutations = [
  {
    opId: crypto.randomUUID(),
    entity: "day_types",
    entityId: ids.dayType,
    type: "delete",
    baseVersion: Number(updatedDocs.dayType.version || createdDocs.dayType.version || 0),
    updatedAtClient: new Date().toISOString()
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_styles",
    entityId: ids.style,
    type: "delete",
    baseVersion: Number(updatedDocs.style.version || createdDocs.style.version || 0),
    updatedAtClient: new Date().toISOString()
  },
  {
    opId: crypto.randomUUID(),
    entity: "climb_gyms",
    entityId: ids.gym,
    type: "delete",
    baseVersion: Number(updatedDocs.gym.version || createdDocs.gym.version || 0),
    updatedAtClient: new Date().toISOString()
  },
  {
    opId: crypto.randomUUID(),
    entity: "timer_templates",
    entityId: ids.timerTemplate,
    type: "delete",
    baseVersion: Number(updatedDocs.timerTemplate.version || createdDocs.timerTemplate.version || 0),
    updatedAtClient: new Date().toISOString()
  }
];

const deleteResponse = await syncPush({
  url: config.url,
  token: accessToken,
  body: {
    deviceId: `web-data-manager-smoke-${runId}`,
    baseCursor: afterUpdate.lastCursor,
    mutations: deleteMutations
  }
});
assertPushAccepted(deleteResponse, deleteMutations.map((mutation) => mutation.opId), "delete");

const afterDelete = await pullUntilExhausted({
  url: config.url,
  token: accessToken,
  startCursor: afterUpdate.lastCursor,
  limit: config.limit
});

assertDelete(afterDelete.changes, "day_types", ids.dayType);
assertDelete(afterDelete.changes, "climb_styles", ids.style);
assertDelete(afterDelete.changes, "climb_gyms", ids.gym);
assertDelete(afterDelete.changes, "timer_templates", ids.timerTemplate);

console.log(
  JSON.stringify(
    {
      ok: true,
      email: config.email,
      checks: {
        createAllGroups: true,
        updateAllGroups: true,
        updateDayTypeName: true,
        deleteAllGroups: true
      }
    },
    null,
    2
  )
);

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

function assertPushAccepted(payload, opIds, label) {
  const failed = Array.isArray(payload.failed) ? payload.failed : [];
  const conflicts = Array.isArray(payload.conflicts) ? payload.conflicts : [];
  const acked = new Set(Array.isArray(payload.acknowledgedOpIds) ? payload.acknowledgedOpIds : []);

  if (failed.length > 0) {
    throw new Error(`${label} push returned failed: ${JSON.stringify(failed)}`);
  }
  if (conflicts.length > 0) {
    throw new Error(`${label} push returned conflicts: ${JSON.stringify(conflicts)}`);
  }
  for (const opId of opIds) {
    if (!acked.has(opId)) {
      throw new Error(`${label} push did not acknowledge opId ${opId}`);
    }
  }
}

function findEntityDoc(changes, entity, entityId) {
  for (const change of changes) {
    if (change.entity !== entity || change.type !== "upsert") {
      continue;
    }
    const doc = change.doc;
    if (doc?.id === entityId) {
      return doc;
    }
  }
  return null;
}

function assertDoc(doc, label) {
  if (!doc || typeof doc !== "object") {
    throw new Error(`${label} verification failed: document not found in pull changes.`);
  }
}

function assertDelete(changes, entity, entityId) {
  const found = changes.some((change) => change.entity === entity && change.type === "delete" && change.entityId === entityId);
  if (!found) {
    throw new Error(`${entity} delete verification failed for id ${entityId}.`);
  }
}
