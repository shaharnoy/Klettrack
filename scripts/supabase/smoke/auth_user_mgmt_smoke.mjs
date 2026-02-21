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
  email: process.env.SUPABASE_TEST_EMAIL.trim(),
  password: process.env.SUPABASE_TEST_PASSWORD
};

const auth = await signIn(config);
const changePasswordResult = await updatePassword(config, auth.access_token, config.password);
const deleteResult = await deleteAccountDryRun(config, auth.access_token);

console.log(JSON.stringify({
  ok: true,
  email: config.email,
  checks: {
    signInWorked: Boolean(auth?.access_token),
    changePasswordHandled: changePasswordResult.ok,
    deleteAccountHandled: deleteResult.ok
  },
  details: {
    changePassword: changePasswordResult.details,
    deleteAccount: deleteResult.details
  }
}, null, 2));

async function signIn(config) {
  const response = await fetch(`${config.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: config.apikey,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      email: config.email,
      password: config.password
    })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    const reason = payload?.error_description || payload?.msg || response.status;
    throw new Error(`Sign in failed: ${reason}`);
  }
  return payload;
}

async function updatePassword(config, accessToken, nextPassword) {
  try {
    const response = await fetch(`${config.url}/auth/v1/user`, {
      method: "PUT",
      headers: {
        apikey: config.apikey,
        Authorization: `Bearer ${accessToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        password: nextPassword
      })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const reason = payload?.msg || payload?.error_description || payload?.error || `HTTP ${response.status}`;
      return { ok: true, details: { accepted: false, reason } };
    }
    return { ok: true, details: { accepted: true } };
  } catch (error) {
    return { ok: false, details: { accepted: false, reason: error instanceof Error ? error.message : "unknown_error" } };
  }
}

async function deleteAccountDryRun(config, accessToken) {
  try {
    const response = await fetch(`${config.url}/functions/v1/delete-account`, {
      method: "POST",
      headers: {
        apikey: config.apikey,
        Authorization: `Bearer ${accessToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ dryRun: true })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const reason = payload?.reason || payload?.msg || payload?.error_description || payload?.error || `HTTP ${response.status}`;
      return { ok: true, details: { accepted: false, reason } };
    }
    return { ok: true, details: { accepted: true } };
  } catch (error) {
    return { ok: false, details: { accepted: false, reason: error instanceof Error ? error.message : "unknown_error" } };
  }
}
