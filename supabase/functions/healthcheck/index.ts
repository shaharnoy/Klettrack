const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-healthcheck-token",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Vary": "Origin"
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function isAuthorized(req: Request): boolean {
  const expectedToken = (Deno.env.get("HEALTHCHECK_TOKEN") ?? "").trim();
  if (expectedToken.length === 0) {
    return true;
  }

  const suppliedToken = (req.headers.get("x-healthcheck-token") ?? "").trim();
  return suppliedToken === expectedToken;
}

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  if (!isAuthorized(req)) {
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  if (req.method === "HEAD") {
    return new Response(null, {
      status: 200,
      headers: {
        ...corsHeaders,
        "cache-control": "no-store"
      }
    });
  }

  return jsonResponse({
    ok: true,
    service: "supabase-edge-function",
    endpoint: "healthcheck",
    timestamp: new Date().toISOString()
  });
});
