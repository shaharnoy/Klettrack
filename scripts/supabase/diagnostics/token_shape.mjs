#!/usr/bin/env node

const url = process.env.SUPABASE_URL?.trim().replace(/\/$/, "");
const apikey = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
const email = process.env.SUPABASE_TEST_EMAIL?.trim();
const password = process.env.SUPABASE_TEST_PASSWORD;

if (!url || !apikey || !email || !password) {
  console.error("Missing env vars");
  process.exit(1);
}

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
  console.error(JSON.stringify({ ok: false, status: response.status, payload }, null, 2));
  process.exit(1);
}

const token = String(payload.access_token);
const segments = token.split(".");

console.log(
  JSON.stringify(
    {
      ok: true,
      token_length: token.length,
      token_segments: segments.length,
      segment_lengths: segments.map((value) => value.length)
    },
    null,
    2
  )
);
