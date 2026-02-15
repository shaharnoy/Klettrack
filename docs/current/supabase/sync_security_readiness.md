# Supabase Sync Security Readiness (Step 13)

## Auth mode decision
- Edge Function `sync` is deployed with `verify_jwt=false`.
- Requests are still authenticated in-function via `supabase.auth.getUser(token)`.
- Rationale: Supabase guidance for JWT signing keys supports explicit in-function verification patterns.

## Key handling
- Clients use publishable/anon key only.
- No `service_role` usage in iOS/web client code.
- Edge function uses project URL + anon key with user bearer token for RLS-scoped access.

## CORS policy
- Explicit origin allow-list with env override via `SUPABASE_SYNC_ALLOWED_ORIGINS`.
- Disallowed browser origins receive `403 origin_not_allowed`.
- `OPTIONS` preflight is handled with explicit allow-list.

## Current advisor status
- Security advisor warning present: leaked password protection disabled.
- Remediation: enable leaked password protection in Supabase Auth settings.

## Latest validation (2026-02-10)
- Edge Function `sync` deployed as ACTIVE v5.
- Live auth + sync smoke (`<test-email>` / `<test-password>`) passes end-to-end.
- Security advisor currently reports only one warning (`auth_leaked_password_protection`) and no high-severity finding in current report.

## Required pre-GA checks
1. Set production `SUPABASE_SYNC_ALLOWED_ORIGINS`.
2. Enable leaked password protection.
3. Re-run function contract tests and web smoke tests.
4. Confirm no secrets committed in repository history.
