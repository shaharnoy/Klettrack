import { supabaseKey, supabaseURL } from "./supabaseClient.js";

let inMemorySession = null;
const AUTH_SESSION_STORAGE_KEY = "WEB_AUTH_SESSION";

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
  let token = getAccessToken();
  if (!token || !supabaseURL || !supabaseKey) {
    return null;
  }

  let response = await fetch(`${supabaseURL}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${token}`
    }
  });
  if (!response.ok && (response.status === 401 || response.status === 403)) {
    const refreshed = await refreshAccessToken();
    if (refreshed?.access_token) {
      token = refreshed.access_token;
      response = await fetch(`${supabaseURL}/auth/v1/user`, {
        method: "GET",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${token}`
        }
      });
    }
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      clearSession();
    }
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
  if (!inMemorySession) {
    inMemorySession = readStoredSession();
  }
  if (!inMemorySession || typeof inMemorySession !== "object") {
    return null;
  }
  return inMemorySession;
}

function saveSession(sessionLike) {
  const accessToken = String(sessionLike?.access_token || "").trim();
  const refreshToken = String(sessionLike?.refresh_token || "").trim();
  if (!accessToken) {
    return;
  }
  inMemorySession = {
    access_token: accessToken,
    refresh_token: refreshToken || null
  };
  writeStoredSession(inMemorySession);
}

function clearSession() {
  inMemorySession = null;
  clearStoredSession();
}

async function refreshAccessToken() {
  const session = loadSession();
  const refreshToken = String(session?.refresh_token || "").trim();
  if (!refreshToken || !supabaseURL || !supabaseKey) {
    return null;
  }

  const response = await fetch(`${supabaseURL}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      "content-type": "application/json"
    },
    body: JSON.stringify({ refresh_token: refreshToken })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.access_token) {
    clearSession();
    return null;
  }
  saveSession(payload);
  return loadSession();
}

function readStoredSession() {
  try {
    const raw =
      window.localStorage.getItem(AUTH_SESSION_STORAGE_KEY) ||
      window.sessionStorage.getItem(AUTH_SESSION_STORAGE_KEY);
    if (!raw) {
      return null;
    }
    const parsed = JSON.parse(raw);
    const accessToken = String(parsed?.access_token || "").trim();
    const refreshToken = String(parsed?.refresh_token || "").trim();
    if (!accessToken) {
      return null;
    }
    return {
      access_token: accessToken,
      refresh_token: refreshToken || null
    };
  } catch {
    return null;
  }
}

function writeStoredSession(sessionLike) {
  try {
    const payload = JSON.stringify({
      access_token: sessionLike.access_token,
      refresh_token: sessionLike.refresh_token
    });
    window.localStorage.setItem(AUTH_SESSION_STORAGE_KEY, payload);
    window.sessionStorage.setItem(AUTH_SESSION_STORAGE_KEY, payload);
  } catch {}
}

function clearStoredSession() {
  try {
    window.localStorage.removeItem(AUTH_SESSION_STORAGE_KEY);
    window.sessionStorage.removeItem(AUTH_SESSION_STORAGE_KEY);
  } catch {}
}
