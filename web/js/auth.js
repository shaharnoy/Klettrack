import { supabaseKey, supabaseURL } from "./supabaseClient.js";

const SESSION_STORAGE_KEY = "web_supabase_session_v1";

function normalizeIdentifier(identifier) {
  return identifier.trim().toLowerCase();
}

async function resolveEmail(identifier) {
  const normalized = normalizeIdentifier(identifier);
  if (normalized.includes("@")) {
    return normalized;
  }

  const resolverURL = (window.__USERNAME_RESOLVER_URL__ || "").trim();
  if (!resolverURL) {
    throw new Error("Username login is not configured.");
  }

  const url = new URL(resolverURL);
  url.searchParams.set("username", normalized);

  const response = await fetch(url.toString(), {
    method: "GET",
    headers: {
      apikey: (window.__SUPABASE_PUBLISHABLE_KEY__ || "").trim()
    }
  });
  if (!response.ok) {
    throw new Error("Unable to resolve username.");
  }
  const payload = await response.json();
  if (!payload?.email) {
    throw new Error("Username resolution returned no email.");
  }
  return String(payload.email).trim().toLowerCase();
}

export async function getCurrentUser() {
  const token = getAccessToken();
  if (!token || !supabaseURL || !supabaseKey) {
    return null;
  }

  const response = await fetch(`${supabaseURL}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${token}`
    }
  });
  if (!response.ok) {
    clearSession();
    return null;
  }
  const payload = await response.json().catch(() => null);
  return payload?.id ? payload : null;
}

export async function signInWithPassword(identifier, password) {
  if (!supabaseURL || !supabaseKey) {
    throw new Error("Supabase config is missing.");
  }
  const email = await resolveEmail(identifier);
  const response = await fetch(`${supabaseURL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ email, password })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    throw new Error(payload?.error_description || payload?.msg || "Sign in failed.");
  }
  saveSession(payload);
  return payload;
}

export async function signUpWithPassword(email, password) {
  if (!supabaseURL || !supabaseKey) {
    throw new Error("Supabase config is missing.");
  }
  const normalizedEmail = normalizeIdentifier(email);
  if (!normalizedEmail.includes("@")) {
    throw new Error("Registration requires a valid email address.");
  }

  const response = await fetch(`${supabaseURL}/auth/v1/signup`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      email: normalizedEmail,
      password
    })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.msg || payload?.error_description || payload?.error || "Sign up failed.");
  }
  if (payload?.session?.access_token) {
    saveSession(payload.session);
  }
  return payload;
}

export async function requestPasswordReset(identifier, redirectTo = null) {
  if (!supabaseURL || !supabaseKey) {
    throw new Error("Supabase config is missing.");
  }
  const email = await resolveEmail(identifier);
  const response = await fetch(`${supabaseURL}/auth/v1/recover`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      email,
      ...(redirectTo ? { redirect_to: redirectTo } : {})
    })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.msg || payload?.error_description || payload?.error || "Password reset request failed.");
  }
  return payload;
}

export async function updatePassword(newPassword) {
  if (!supabaseURL || !supabaseKey) {
    throw new Error("Supabase config is missing.");
  }
  const token = getAccessToken();
  if (!token) {
    throw new Error("Missing auth session.");
  }
  const response = await fetch(`${supabaseURL}/auth/v1/user`, {
    method: "PUT",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      password: String(newPassword || "")
    })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.msg || payload?.error_description || payload?.error || "Password update failed.");
  }
  return payload;
}

export async function deleteCurrentAccount() {
  if (!supabaseURL || !supabaseKey) {
    throw new Error("Supabase config is missing.");
  }
  const token = getAccessToken();
  if (!token) {
    throw new Error("Missing auth session.");
  }
  const response = await fetch(`${supabaseURL}/functions/v1/delete-account`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ dryRun: false })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 404) {
      throw new Error("Account deletion service is not deployed yet.");
    }
    throw new Error(payload?.reason || payload?.msg || payload?.error_description || payload?.error || "Account deletion failed.");
  }
  clearSession();
  return payload;
}

export async function signOut() {
  const token = getAccessToken();
  if (!token || !supabaseURL || !supabaseKey) {
    clearSession();
    return;
  }
  await fetch(`${supabaseURL}/auth/v1/logout`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${token}`
    }
  }).catch(() => {});
  clearSession();
}

export function getAccessToken() {
  const session = loadSession();
  return session?.access_token || null;
}

function loadSession() {
  try {
    const raw = localStorage.getItem(SESSION_STORAGE_KEY);
    if (!raw) {
      return null;
    }
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function saveSession(sessionLike) {
  const accessToken = String(sessionLike?.access_token || "").trim();
  const refreshToken = String(sessionLike?.refresh_token || "").trim();
  if (!accessToken) {
    return;
  }
  localStorage.setItem(
    SESSION_STORAGE_KEY,
    JSON.stringify({
      access_token: accessToken,
      refresh_token: refreshToken || null
    })
  );
}

function clearSession() {
  localStorage.removeItem(SESSION_STORAGE_KEY);
}
