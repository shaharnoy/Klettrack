#!/usr/bin/env node

const required = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_TEST_EMAIL", "SUPABASE_TEST_PASSWORD"];
for (const key of required) {
  if (!process.env[key] || process.env[key].trim().length === 0) {
    console.error(`Missing env var: ${key}`);
    process.exit(1);
  }
}

const config = {
  url: process.env.SUPABASE_URL.trim().replace(/\/$/, ""),
  apikey: process.env.SUPABASE_PUBLISHABLE_KEY.trim(),
  existingEmail: process.env.SUPABASE_TEST_EMAIL.trim(),
  existingPassword: process.env.SUPABASE_TEST_PASSWORD
};

const newEmail = `codex-register-${Date.now()}@example.com`;
const newPassword = `CodexReg!${Math.floor(Math.random() * 90000 + 10000)}`;

const signupNew = await signUp(config, newEmail, newPassword);
const signupExisting = await signUp(config, config.existingEmail, config.existingPassword);
const loginExisting = await signIn(config, config.existingEmail, config.existingPassword);

console.log(JSON.stringify({
  ok: true,
  checks: {
    signUpNewHandled: signupNew.ok,
    signUpExistingHandled: signupExisting.ok,
    signInExistingWorked: Boolean(loginExisting?.access_token)
  },
  details: {
    signupNew: signupNew.details,
    signupExisting: signupExisting.details
  }
}, null, 2));

async function signUp(config, email, password) {
  try {
    const response = await fetch(`${config.url}/auth/v1/signup`, {
      method: "POST",
      headers: {
        apikey: config.apikey,
        "content-type": "application/json"
      },
      body: JSON.stringify({ email, password })
    });
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      const message = payload?.msg || payload?.error_description || payload?.error || `HTTP ${response.status}`;
      return { ok: true, details: { accepted: false, message } };
    }
    return {
      ok: true,
      details: {
        accepted: true,
        userId: payload?.user?.id || null,
        hasSession: Boolean(payload?.session)
      }
    };
  } catch (error) {
    return {
      ok: false,
      details: {
        accepted: false,
        message: error instanceof Error ? error.message : "unknown_error"
      }
    };
  }
}

async function signIn(config, email, password) {
  const response = await fetch(`${config.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: config.apikey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ email, password })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    const reason = payload?.error_description || payload?.msg || response.status;
    throw new Error(`Sign in failed: ${reason}`);
  }
  return payload;
}
