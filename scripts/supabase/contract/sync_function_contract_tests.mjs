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
  secondaryEmail: process.env.SUPABASE_SECONDARY_TEST_EMAIL?.trim(),
  secondaryPassword: process.env.SUPABASE_SECONDARY_TEST_PASSWORD,
  limit: 200
};

const runId = crypto.randomUUID();
const activityId = crypto.randomUUID();
const activityName = `contract-${Date.now()}`;
const sessionId = crypto.randomUUID();
const timerTemplateId = crypto.randomUUID();
const timerIntervalId = crypto.randomUUID();
const invalidTimerIntervalId = crypto.randomUUID();
const timerSessionId = crypto.randomUUID();
const timerLapId = crypto.randomUUID();
const invalidTimerLapId = crypto.randomUUID();
const sessionItemId = crypto.randomUUID();
const climbEntryId = crypto.randomUUID();
const climbMediaId = crypto.randomUUID();
const invalidClimbMediaId = crypto.randomUUID();
const climbStyleId = crypto.randomUUID();
const climbGymId = crypto.randomUUID();
const runCursor = new Date(Date.now() - 60_000).toISOString();

const primarySession = await signInWithPassword({
  url: config.url,
  apikey: config.apikey,
  email: config.primaryEmail,
  password: config.primaryPassword
});

const secondarySession = await resolveSecondarySession(config);

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

const timerSessionCreateOpId = crypto.randomUUID();
const timerSessionCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: timerSessionCreateOpId,
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
assertAcked(timerSessionCreateResponse, timerSessionCreateOpId, "timer_session_create");

const timerLapCreateOpId = crypto.randomUUID();
const timerLapCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: timerLapCreateOpId,
        entity: "timer_laps",
        entityId: timerLapId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          timer_session_id: timerSessionId,
          lap_number: 1,
          timestamp: new Date().toISOString(),
          elapsed_seconds: 45
        }
      }
    ]
  }
});
assertAcked(timerLapCreateResponse, timerLapCreateOpId, "timer_lap_create");

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

const invalidTimerLapOpId = crypto.randomUUID();
const invalidTimerLapResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: invalidTimerLapOpId,
        entity: "timer_laps",
        entityId: invalidTimerLapId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          timer_session_id: crypto.randomUUID(),
          lap_number: 1,
          timestamp: new Date().toISOString(),
          elapsed_seconds: 10
        }
      }
    ]
  }
});
assertMutationFailed(invalidTimerLapResponse, invalidTimerLapOpId, "invalid_parent_reference", "timer_lap_invalid_parent");

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

const climbMediaCreateOpId = crypto.randomUUID();
const climbMediaCreateResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: climbMediaCreateOpId,
        entity: "climb_media",
        entityId: climbMediaId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          climb_entry_id: climbEntryId,
          type: "video",
          created_at: new Date().toISOString(),
          storage_bucket: "climb-media",
          storage_path: `contract/${runId}.mp4`
        }
      }
    ]
  }
});
assertAcked(climbMediaCreateResponse, climbMediaCreateOpId, "climb_media_create");

const invalidClimbMediaOpId = crypto.randomUUID();
const invalidClimbMediaResponse = await syncPush({
  url: config.url,
  token: primarySession.access_token,
  body: {
    deviceId: `contract-primary-${runId}`,
    baseCursor: primaryAfterCreate.lastCursor,
    mutations: [
      {
        opId: invalidClimbMediaOpId,
        entity: "climb_media",
        entityId: invalidClimbMediaId,
        type: "upsert",
        baseVersion: 0,
        updatedAtClient: new Date().toISOString(),
        payload: {
          climb_entry_id: crypto.randomUUID(),
          type: "photo",
          created_at: new Date().toISOString(),
          storage_bucket: "climb-media",
          storage_path: `contract/${runId}.jpg`
        }
      }
    ]
  }
});
assertMutationFailed(invalidClimbMediaResponse, invalidClimbMediaOpId, "invalid_parent_reference", "climb_media_invalid_parent");

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

let ownershipReadIsolation = false;
let ownershipWriteBlocked = false;
let secondaryChecksSkipped = false;

if (secondarySession) {
  const secondaryAfterPrimaryCreate = await pullUntilExhausted({
    url: config.url,
    token: secondarySession.access_token,
    startCursor: runCursor,
    limit: config.limit
  });

  const leakedToSecondary = findActivityDoc(secondaryAfterPrimaryCreate.changes, activityId);
  if (leakedToSecondary) {
    throw new Error("Ownership isolation failed: secondary user can see primary user row.");
  }
  ownershipReadIsolation = true;

  const secondaryDeleteOp = crypto.randomUUID();
  const secondaryDeleteResponse = await syncPush({
    url: config.url,
    token: secondarySession.access_token,
    body: {
      deviceId: `contract-secondary-${runId}`,
      baseCursor: secondaryAfterPrimaryCreate.lastCursor,
      mutations: [
        {
          opId: secondaryDeleteOp,
          entity: "activities",
          entityId: activityId,
          type: "delete",
          baseVersion: Number(createdDoc.version ?? 1),
          updatedAtClient: new Date().toISOString()
        }
      ]
    }
  });

  ownershipWriteBlocked =
    !(secondaryDeleteResponse.acknowledgedOpIds ?? []).includes(secondaryDeleteOp) &&
    (((secondaryDeleteResponse.conflicts ?? []).length > 0) || ((secondaryDeleteResponse.failed ?? []).length > 0));

  if (!ownershipWriteBlocked) {
    throw new Error("Ownership enforcement failed: secondary user mutation unexpectedly acknowledged.");
  }
} else {
  secondaryChecksSkipped = true;
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

const timerSessionDoc = findEntityDoc(v2AfterCreate.changes, "timer_sessions", timerSessionId);
if (!timerSessionDoc) {
    throw new Error("Timer session upsert verification failed.");
}

const timerLapDoc = findEntityDoc(v2AfterCreate.changes, "timer_laps", timerLapId);
if (!timerLapDoc) {
    throw new Error("Timer lap upsert verification failed.");
}

const sessionItemDoc = findEntityDoc(v2AfterCreate.changes, "session_items", sessionItemId);
if (!sessionItemDoc) {
    throw new Error("Session item upsert verification failed.");
}

const climbEntryDoc = findEntityDoc(v2AfterCreate.changes, "climb_entries", climbEntryId);
if (!climbEntryDoc) {
  throw new Error("Climb entry upsert verification failed.");
}

const climbMediaDoc = findEntityDoc(v2AfterCreate.changes, "climb_media", climbMediaId);
if (!climbMediaDoc) {
  throw new Error("Climb media upsert verification failed.");
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
        entity: "climb_media",
        entityId: climbMediaId,
        type: "delete",
        baseVersion: Number(climbMediaDoc.version ?? 1),
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
        entity: "timer_laps",
        entityId: timerLapId,
        type: "delete",
        baseVersion: Number(timerLapDoc.version ?? 1),
        updatedAtClient: new Date().toISOString()
      },
      {
        opId: crypto.randomUUID(),
        entity: "timer_sessions",
        entityId: timerSessionId,
        type: "delete",
        baseVersion: Number(timerSessionDoc.version ?? 1),
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
    idempotentReplay: true,
    versionConflict: true,
    ownershipReadIsolation,
    ownershipWriteBlocked,
    v2EntityContract: true,
    parentValidation: true,
    secondaryChecksSkipped,
    cleanup: true
  },
  primaryEmail: config.primaryEmail,
  secondaryEmail: secondarySession?.email ?? null
}, null, 2));

async function resolveSecondarySession({ url, apikey, secondaryEmail, secondaryPassword }) {
  if (secondaryEmail && secondaryPassword) {
    return await signInWithPassword({
      url,
      apikey,
      email: secondaryEmail,
      password: secondaryPassword
    });
  }

  const generatedEmail = `codex-sync-${Date.now()}-${Math.floor(Math.random() * 10000)}@example.com`;
  const generatedPassword = `Codex!${crypto.randomUUID()}`;

  const created = await signUp({
    url,
    apikey,
    email: generatedEmail,
    password: generatedPassword,
    allowFailure: true
  });

  if (created?.access_token) {
    return { ...created, email: generatedEmail };
  }

  const signedIn = await signInWithPassword({
    url,
    apikey,
    email: generatedEmail,
    password: generatedPassword,
    allowFailure: true
  });

  return signedIn;
}

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

async function signUp({ url, apikey, email, password, allowFailure = false }) {
  const response = await fetch(`${url}/auth/v1/signup`, {
    method: "POST",
    headers: {
      apikey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ email, password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (allowFailure) {
      return null;
    }
    throw new Error(`Sign-up failed for ${email}: ${payload?.error_description || payload?.msg || response.status}`);
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
