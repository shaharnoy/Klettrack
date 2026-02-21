const DEFAULT_ALLOWED_ORIGINS = [
  "https://klettrack.com",
  "https://www.klettrack.com",
  "http://localhost:3000",
  "http://localhost:5173"
];

function normalizedOrigins(values: string[]): string[] {
  const unique = new Set(
    values
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
  );
  return Array.from(unique);
}

export function allowedOrigins(): string[] {
  const explicit = Deno.env.get("SUPABASE_SYNC_ALLOWED_ORIGINS") ?? "";
  if (explicit.trim().length > 0) {
    return normalizedOrigins(explicit.split(","));
  }

  return normalizedOrigins(DEFAULT_ALLOWED_ORIGINS);
}

export function isOriginAllowed(origin: string | null): boolean {
  if (!origin) {
    return false;
  }

  return allowedOrigins().includes(origin.trim());
}

export function corsHeadersForOrigin(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin"
  };

  if (origin && isOriginAllowed(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }

  return headers;
}
