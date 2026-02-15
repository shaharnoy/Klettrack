import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeadersForOrigin, isOriginAllowed } from "./_shared/cors.ts";

type DeleteAccountRequest = {
  dryRun?: boolean;
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

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse(req, { error: "server_misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse(req, { error: "unauthorized" }, 401);
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    return jsonResponse(req, { error: "unauthorized" }, 401);
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey);

  const userLookup = await adminClient.auth.getUser(token);
  if (userLookup.error || !userLookup.data.user?.id) {
    return jsonResponse(req, { error: "unauthorized" }, 401);
  }
  const userId = userLookup.data.user.id;

  let body: DeleteAccountRequest = {};
  try {
    body = (await req.json()) as DeleteAccountRequest;
  } catch {
    body = {};
  }

  if (body.dryRun === true) {
    return jsonResponse(req, {
      ok: true,
      dryRun: true,
      userId
    });
  }

  const deleteResult = await adminClient.auth.admin.deleteUser(userId);
  if (deleteResult.error) {
    return jsonResponse(req, { error: "delete_failed", reason: deleteResult.error.message }, 500);
  }

  return jsonResponse(req, { ok: true, deletedUserId: userId });
});

function jsonResponse(req: Request, body: Record<string, unknown>, status = 200): Response {
  const origin = req.headers.get("Origin");
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...corsHeadersForOrigin(origin)
    }
  });
}
