import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { corsHeadersForOrigin, isOriginAllowed } from "./_shared/cors.ts";

type EntityName =
  | "plan_kinds"
  | "day_types"
  | "plans"
  | "plan_days"
  | "activities"
  | "training_types"
  | "exercises"
  | "boulder_combinations"
  | "boulder_combination_exercises"
  | "sessions"
  | "session_items"
  | "timer_templates"
  | "timer_intervals"
  | "timer_sessions"
  | "timer_laps"
  | "climb_entries"
  | "climb_styles"
  | "climb_gyms";

type MutationType = "upsert" | "delete";

type PushMutation = {
  opId: string;
  entity: EntityName;
  entityId: string;
  type: MutationType;
  baseVersion: number;
  updatedAtClient?: string;
  payload?: Record<string, unknown>;
};

type PushRequest = {
  deviceId?: string;
  baseCursor?: string;
  mutations: PushMutation[];
};

type PullRequest = {
  cursor?: string;
  limit?: number;
};

const ENTITY_TABLES: ReadonlySet<string> = new Set([
  "plan_kinds",
  "day_types",
  "plans",
  "plan_days",
  "activities",
  "training_types",
  "exercises",
  "boulder_combinations",
  "boulder_combination_exercises",
  "sessions",
  "session_items",
  "timer_templates",
  "timer_intervals",
  "timer_sessions",
  "timer_laps",
  "climb_entries",
  "climb_styles",
  "climb_gyms"
]);

const MAX_MUTATIONS_PER_PUSH = 200;
const MAX_PULL_LIMIT = 500;

type UserScopedClient = {
  client: SupabaseClient;
  userId: string;
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    if (!isOriginAllowed(origin)) {
      return jsonResponse(req, { error: "origin_not_allowed" }, 403);
    }
    return new Response("ok", { headers: corsHeadersForOrigin(origin) });
  }

  if (origin && !isOriginAllowed(origin)) {
    return jsonResponse(req, { error: "origin_not_allowed" }, 403);
  }

  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method_not_allowed" }, 405);
  }

  const scoped = await getUserScopedClient(req);
  if (!scoped) {
    return jsonResponse(req, { error: "unauthorized" }, 401);
  }

  const url = new URL(req.url);

  try {
    if (url.pathname.endsWith("/push")) {
      const body = (await req.json()) as PushRequest;
      return await handlePush(req, scoped.client, scoped.userId, body);
    }

    if (url.pathname.endsWith("/pull")) {
      const body = (await req.json()) as PullRequest;
      return await handlePull(req, scoped.client, scoped.userId, body);
    }

    return jsonResponse(req, { error: "not_found" }, 404);
  } catch {
    return jsonResponse(req, { error: "invalid_request" }, 400);
  }
});

async function getUserScopedClient(req: Request): Promise<UserScopedClient | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    return null;
  }

  const projectUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const projectKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  if (!projectUrl || !projectKey) {
    return null;
  }

  const authClient = createClient(projectUrl, projectKey);
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user?.id) {
    return null;
  }
  const userId = authData.user.id;

  const client = createClient(projectUrl, projectKey, {
    global: { headers: { Authorization: authHeader } }
  });

  return { client, userId };
}

async function handlePush(req: Request, client: SupabaseClient, userId: string, body: PushRequest): Promise<Response> {
  if (!Array.isArray(body?.mutations)) {
    return jsonResponse(req, { error: "invalid_mutations" }, 400);
  }

  if (body.mutations.length > MAX_MUTATIONS_PER_PUSH) {
    return jsonResponse(req, { error: "too_many_mutations" }, 413);
  }

  const acknowledgedOpIds: string[] = [];
  const conflicts: Array<Record<string, unknown>> = [];
  const failed: Array<Record<string, unknown>> = [];

  for (const mutation of body.mutations) {
    const validated = validateMutation(mutation);
    if (!validated.ok) {
      failed.push({ opId: mutation?.opId, reason: validated.reason });
      continue;
    }

    const table = mutation.entity;
    const mutationPayload = validated.payload;

    const parentValidationError = await validateParentReferences({
      client,
      userId,
      entity: mutation.entity,
      payload: mutationPayload
    });
    if (parentValidationError) {
      failed.push({ opId: mutation.opId, reason: parentValidationError });
      continue;
    }

    const { data: existing, error: fetchError } = await client
      .from(table)
      .select("id, owner_id, version, is_deleted, last_op_id")
      .eq("id", mutation.entityId)
      .eq("owner_id", userId)
      .maybeSingle();

    if (fetchError) {
      failed.push({ opId: mutation.opId, reason: "fetch_failed" });
      continue;
    }

    if (existing && existing.last_op_id === mutation.opId) {
      acknowledgedOpIds.push(mutation.opId);
      continue;
    }

    if (!existing) {
      if (mutation.baseVersion !== 0) {
        conflicts.push({
          opId: mutation.opId,
          entity: table,
          entityId: mutation.entityId,
          reason: "version_mismatch",
          serverVersion: null,
          serverDoc: null
        });
        continue;
      }

      const insertPayload: Record<string, unknown> = {
        id: mutation.entityId,
        owner_id: userId,
        updated_at_client: mutation.updatedAtClient ?? null,
        last_op_id: mutation.opId,
        is_deleted: mutation.type === "delete"
      };

      if (mutation.type === "upsert" && mutationPayload) {
        Object.assign(insertPayload, mutationPayload);
      }

      const { error: insertError } = await client.from(table).insert(insertPayload);
      if (insertError) {
        if (table === "boulder_combination_exercises" && insertError.code === "23505") {
          acknowledgedOpIds.push(mutation.opId);
          continue;
        }
        failed.push({ opId: mutation.opId, reason: "insert_failed" });
        continue;
      }

      acknowledgedOpIds.push(mutation.opId);
      continue;
    }

    if (mutation.baseVersion !== existing.version) {
      const { data: serverDoc } = await client
        .from(table)
        .select("*")
        .eq("id", mutation.entityId)
        .eq("owner_id", userId)
        .maybeSingle();

      conflicts.push({
        opId: mutation.opId,
        entity: table,
        entityId: mutation.entityId,
        reason: "version_mismatch",
        serverVersion: existing.version,
        serverDoc
      });
      continue;
    }

    const updatePayload: Record<string, unknown> = {
      updated_at_client: mutation.updatedAtClient ?? null,
      last_op_id: mutation.opId
    };

    if (mutation.type === "delete") {
      updatePayload.is_deleted = true;
    } else if (mutationPayload) {
      Object.assign(updatePayload, mutationPayload);
      updatePayload.is_deleted = false;
    }

    const { error: updateError } = await client
      .from(table)
      .update(updatePayload)
      .eq("id", mutation.entityId)
      .eq("owner_id", userId);

    if (updateError) {
      failed.push({ opId: mutation.opId, reason: "update_failed" });
      continue;
    }

    acknowledgedOpIds.push(mutation.opId);
  }

  return jsonResponse(req, {
    acknowledgedOpIds,
    conflicts,
    failed,
    newCursor: new Date().toISOString()
  });
}

async function handlePull(req: Request, client: SupabaseClient, userId: string, body: PullRequest): Promise<Response> {
  const requestedLimit = Number.isFinite(body?.limit) ? Number(body.limit) : 200;
  const limit = Math.max(1, Math.min(requestedLimit, MAX_PULL_LIMIT));
  const cursor = body?.cursor;

  const { data, error } = await client.rpc("sync_pull_page", {
    p_owner_id: userId,
    p_cursor: cursor ?? null,
    p_limit: limit
  });

  if (error) {
    return jsonResponse(req, { error: "pull_failed" }, 500);
  }

  const row = Array.isArray(data) ? data[0] : data;
  const changes = Array.isArray(row?.changes) ? row.changes : [];
  const nextCursor =
    typeof row?.next_cursor === "string"
      ? row.next_cursor
      : (cursor ?? new Date(0).toISOString());
  const hasMore = Boolean(row?.has_more);

  return jsonResponse(req, {
    changes,
    nextCursor,
    hasMore
  });
}

type MutationValidationResult =
  | { ok: true; payload?: Record<string, unknown> }
  | { ok: false; reason: string };

const ENTITY_FIELD_ALLOWLIST: Record<EntityName, readonly string[]> = {
  plan_kinds: ["key", "name", "total_weeks", "is_repeating", "display_order"],
  day_types: ["key", "name", "display_order", "color_key", "is_default", "is_hidden"],
  plans: [
    "name",
    "kind_id",
    "start_date",
    "recurring_chosen_exercises_by_weekday",
    "recurring_exercise_order_by_weekday",
    "recurring_day_type_id_by_weekday"
  ],
  plan_days: ["plan_id", "day_date", "day_type_id", "chosen_exercise_ids", "exercise_order_by_id", "daily_notes"],
  activities: ["name"],
  training_types: ["activity_id", "name", "area", "type_description"],
  exercises: ["training_type_id", "name", "area", "display_order", "exercise_description", "reps_text", "duration_text", "sets_text", "rest_text", "notes"],
  boulder_combinations: ["training_type_id", "name", "combo_description"],
  boulder_combination_exercises: ["boulder_combination_id", "exercise_id", "display_order"],
  sessions: ["session_date"],
  session_items: ["session_id", "source_tag", "exercise_name", "sort_order", "plan_source_id", "plan_name", "reps", "sets", "weight_kg", "grade", "notes", "duration"],
  timer_templates: ["name", "template_description", "total_time_seconds", "is_repeating", "repeat_count", "rest_time_between_intervals", "created_date", "last_used_date", "use_count"],
  timer_intervals: ["timer_template_id", "name", "work_time_seconds", "rest_time_seconds", "repetitions", "display_order"],
  timer_sessions: ["start_date", "end_date", "timer_template_id", "template_name", "plan_day_id", "total_elapsed_seconds", "completed_intervals", "was_completed", "daily_notes"],
  timer_laps: ["timer_session_id", "lap_number", "timestamp", "elapsed_seconds", "notes"],
  climb_entries: [
    "climb_type",
    "rope_climb_type",
    "grade",
    "feels_like_grade",
    "angle_degrees",
    "style",
    "attempts",
    "is_work_in_progress",
    "is_previously_climbed",
    "hold_color",
    "gym",
    "notes",
    "date_logged",
    "tb2_climb_uuid"
  ],
  climb_styles: ["name", "is_default", "is_hidden"],
  climb_gyms: ["name", "is_default"]
};

const REQUIRED_UPSERT_FIELDS: Partial<Record<EntityName, readonly string[]>> = {
  plan_kinds: ["key", "name"],
  day_types: ["key", "name", "color_key"],
  plans: ["name", "start_date"],
  plan_days: ["day_date"],
  activities: ["name"],
  training_types: ["name"],
  exercises: ["name"],
  boulder_combinations: ["name"],
  boulder_combination_exercises: ["boulder_combination_id", "exercise_id"],
  sessions: ["session_date"],
  session_items: ["exercise_name"],
  timer_templates: ["name", "created_date", "is_repeating", "use_count"],
  timer_intervals: ["name", "work_time_seconds", "rest_time_seconds", "repetitions"],
  timer_sessions: ["start_date", "total_elapsed_seconds", "completed_intervals", "was_completed"],
  timer_laps: ["lap_number", "timestamp", "elapsed_seconds"],
  climb_entries: ["climb_type", "grade", "style", "gym", "date_logged", "is_work_in_progress"],
  climb_styles: ["name", "is_default"],
  climb_gyms: ["name", "is_default"]
};

function validateMutation(mutation: PushMutation): MutationValidationResult {
  if (!mutation || typeof mutation !== "object") {
    return { ok: false, reason: "invalid_mutation" };
  }

  if (typeof mutation.opId !== "string" || mutation.opId.length < 10) {
    return { ok: false, reason: "invalid_op_id" };
  }

  if (typeof mutation.entityId !== "string" || mutation.entityId.length < 10) {
    return { ok: false, reason: "invalid_entity_id" };
  }

  if (typeof mutation.baseVersion !== "number" || mutation.baseVersion < 0) {
    return { ok: false, reason: "invalid_base_version" };
  }

  if (!ENTITY_TABLES.has(mutation.entity)) {
    return { ok: false, reason: "invalid_entity" };
  }

  if (mutation.type !== "upsert" && mutation.type !== "delete") {
    return { ok: false, reason: "invalid_mutation_type" };
  }

  if (mutation.type === "upsert") {
    if (!mutation.payload || typeof mutation.payload !== "object" || Array.isArray(mutation.payload)) {
      return { ok: false, reason: "invalid_payload" };
    }
    const payloadResult = sanitizePayload(mutation.entity, mutation.payload);
    if (!payloadResult.ok) {
      return payloadResult;
    }
    return { ok: true, payload: payloadResult.payload };
  }

  return { ok: true };
}

function sanitizePayload(entity: EntityName, payload: Record<string, unknown>): MutationValidationResult {
  const allowlist = new Set(ENTITY_FIELD_ALLOWLIST[entity] ?? []);
  const sanitized: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(payload)) {
    if (!allowlist.has(key)) {
      return { ok: false, reason: "invalid_payload_field" };
    }
    sanitized[key] = value;
  }

  for (const requiredField of REQUIRED_UPSERT_FIELDS[entity] ?? []) {
    if (!(requiredField in sanitized)) {
      return { ok: false, reason: "missing_required_field" };
    }
  }

  return { ok: true, payload: sanitized };
}

async function validateParentReferences(args: {
  client: SupabaseClient;
  userId: string;
  entity: EntityName;
  payload?: Record<string, unknown>;
}): Promise<string | null> {
  const { client, userId, entity, payload } = args;
  if (!payload) {
    return null;
  }

  const parentChecks: Array<Promise<boolean>> = [];

  const pushCheck = (table: EntityName, value: unknown) => {
    if (typeof value !== "string" || value.length < 10) {
      return;
    }
    parentChecks.push(validateOwnerLinkedRow(client, userId, table, value));
  };

  switch (entity) {
    case "plans":
      pushCheck("plan_kinds", payload.kind_id);
      break;
    case "plan_days":
      pushCheck("plans", payload.plan_id);
      pushCheck("day_types", payload.day_type_id);
      break;
    case "training_types":
      pushCheck("activities", payload.activity_id);
      break;
    case "exercises":
      pushCheck("training_types", payload.training_type_id);
      break;
    case "boulder_combinations":
      pushCheck("training_types", payload.training_type_id);
      break;
    case "boulder_combination_exercises":
      pushCheck("boulder_combinations", payload.boulder_combination_id);
      pushCheck("exercises", payload.exercise_id);
      break;
    case "session_items":
      pushCheck("sessions", payload.session_id);
      break;
    case "timer_intervals":
      pushCheck("timer_templates", payload.timer_template_id);
      break;
    case "timer_sessions":
      pushCheck("timer_templates", payload.timer_template_id);
      pushCheck("plan_days", payload.plan_day_id);
      break;
    case "timer_laps":
      pushCheck("timer_sessions", payload.timer_session_id);
      break;
    default:
      break;
  }

  if (parentChecks.length === 0) {
    return null;
  }

  const results = await Promise.all(parentChecks);
  return results.every(Boolean) ? null : "invalid_parent_reference";
}

async function validateOwnerLinkedRow(
  client: SupabaseClient,
  userId: string,
  table: EntityName,
  id: string
): Promise<boolean> {
  const { data, error } = await client
    .from(table)
    .select("id")
    .eq("id", id)
    .eq("owner_id", userId)
    .maybeSingle();

  if (error) {
    return false;
  }
  return Boolean(data?.id);
}

function jsonResponse(req: Request, body: Record<string, unknown>, status = 200): Response {
  const origin = req.headers.get("Origin");
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeadersForOrigin(origin),
      "Content-Type": "application/json"
    }
  });
}
