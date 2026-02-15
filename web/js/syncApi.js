import { supabaseURL } from "./supabaseClient.js";
import { getAccessToken } from "./auth.js";

const DEFAULT_LIMIT = 200;

export async function syncPush({ deviceId, baseCursor, mutations }) {
  return syncPost("/push", {
    deviceId,
    baseCursor,
    mutations
  });
}

export async function syncPull({ cursor, limit = DEFAULT_LIMIT }) {
  return syncPost("/pull", {
    cursor,
    limit
  });
}

async function syncPost(path, body) {
  if (!supabaseURL.startsWith("https://")) {
    throw new Error("Sync endpoint must use HTTPS.");
  }
  const token = getAccessToken();
  if (!token) {
    throw new Error("Missing auth session.");
  }

  const response = await fetch(`${supabaseURL}/functions/v1/sync${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(body)
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = payload?.error ? String(payload.error) : `HTTP ${response.status}`;
    throw new Error(`Sync error: ${reason}`);
  }

  return payload;
}
