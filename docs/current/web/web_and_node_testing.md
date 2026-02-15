# Web UI + Node Test Guide

This guide explains how to:
- Run the web app locally.
- Configure Supabase credentials for local web testing.
- Run the Node-based sync validation scripts.

## 1. Run Web UI Locally

From the repository root:

```bash
cd <repo-root>
python3 -m http.server 5173
```

Open:
- `http://localhost:5173/app.html`

Notes:
- Allowed local origins for the deployed function CORS include `http://localhost:3000` and `http://localhost:5173`.
- If port `5173` is busy, use `3000`.

## 2. Configure Supabase in Browser (One-Time per Origin)

Open browser DevTools Console on `app.html` and run:

```js
localStorage.setItem("SUPABASE_URL", "<project-url>");
localStorage.setItem("SUPABASE_PUBLISHABLE_KEY", "<publishable-key>");
localStorage.setItem("SUPABASE_USERNAME_RESOLVER_URL", "");
location.reload();
```

Then sign in from the web UI.

## 3. Optional: Enable Realtime Auto-Refresh in Web

By default, manual page refresh may still be needed. To enable realtime-triggered pull:

```js
localStorage.setItem("SYNC_REALTIME_ENABLED", "true");
location.reload();
```

To disable:

```js
localStorage.setItem("SYNC_REALTIME_ENABLED", "false");
location.reload();
```

## 4. Run Node Sync Tests

All commands below are run from repo root:

```bash
cd <repo-root>
```

### 4.1 Web Smoke Test

Validates:
- Auth sign-in
- Push upsert
- Pull verification
- Push delete
- Pull tombstone verification

```bash
export SUPABASE_URL='<project-url>'
export SUPABASE_PUBLISHABLE_KEY='<publishable-key>'
export SUPABASE_TEST_EMAIL='<test-email>'
export SUPABASE_TEST_PASSWORD='<test-password>'
node scripts/supabase/smoke/sync_web_smoke.mjs
```

### 4.2 Function Contract Test

Validates:
- Idempotent replay
- Version conflict behavior
- Cleanup
- Ownership isolation checks (if secondary account is available)

```bash
export SUPABASE_URL='<project-url>'
export SUPABASE_PUBLISHABLE_KEY='<publishable-key>'
export SUPABASE_TEST_EMAIL='<test-email>'
export SUPABASE_TEST_PASSWORD='<test-password>'
node scripts/supabase/contract/sync_function_contract_tests.mjs
```

Optional secondary user credentials:

```bash
export SUPABASE_SECONDARY_TEST_EMAIL='<secondary-test-email>'
export SUPABASE_SECONDARY_TEST_PASSWORD='<secondary-test-password>'
```

If not provided, the script attempts auto-signup; if rate-limited, secondary checks are skipped.

### 4.3 Scale Validation Test

Validates:
- Batched upserts
- Pull pagination under load
- Delete tombstones

```bash
export SUPABASE_URL='<project-url>'
export SUPABASE_PUBLISHABLE_KEY='<publishable-key>'
export SUPABASE_TEST_EMAIL='<test-email>'
export SUPABASE_TEST_PASSWORD='<test-password>'
export SUPABASE_SCALE_UPSERT_COUNT='120'
node scripts/supabase/diagnostics/sync_scale_validation.mjs
```

## 5. Quick Troubleshooting

### Address already in use

If local server fails with port-in-use:

```bash
python3 -m http.server 3000
```

### CSP error loading `esm.sh`

Use the current `app.html` from this repo; CSP has been updated to allow:
- `script-src` from `https://esm.sh`
- `connect-src` to `https://*.supabase.co` and `wss://*.supabase.co`

### Web UI says Supabase config missing

Re-run the Console `localStorage.setItem(...)` commands and reload.

### iOS sync says synced but web not updated

- Press `Sync Now` in iOS app.
- Ensure web realtime is enabled (or refresh manually).
- Confirm using the same account (`<test-email>`) on both clients.
