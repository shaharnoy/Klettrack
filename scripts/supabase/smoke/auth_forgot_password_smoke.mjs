#!/usr/bin/env node

const required = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_TEST_EMAIL"];
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
  redirectTo: process.env.SUPABASE_RESET_REDIRECT || `${process.env.SUPABASE_URL.trim().replace(/\/$/, "")}/app.html#/login`
};

const response = await fetch(`${config.url}/auth/v1/recover`, {
  method: "POST",
  headers: {
    apikey: config.apikey,
    "content-type": "application/json"
  },
  body: JSON.stringify({
    email: config.email,
    redirect_to: config.redirectTo
  })
});

const payload = await response.json().catch(() => ({}));
const reason = payload?.msg || payload?.error_description || payload?.error || `HTTP ${response.status}`;
const accepted = response.ok;

console.log(JSON.stringify({
  ok: true,
  email: config.email,
  checks: {
    recoverRequestHandled: true
  },
  details: {
    accepted,
    reason
  }
}, null, 2));
