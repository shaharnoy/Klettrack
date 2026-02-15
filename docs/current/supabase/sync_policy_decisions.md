# Supabase Sync Policy Decisions

Date: February 15, 2026

## Confirmed decisions

1. Tombstone retention: 30 days.
2. Unknown delete handling on pull: ignore unknown IDs (no placeholder creation).
3. Edge function auth hardening: keep `verify_jwt=false` and use explicit Supabase auth verification (`auth.getUser`) in-function.
4. Leaked password protection: intentionally left disabled for now.
5. Unused indexes: keep in place; review after real workload metrics.
6. Rollout: manual rollout control (no fixed telemetry gates required in code right now).
7. Web onboarding: app-first only. Web signup remains disabled and web login instructs users to create accounts in iOS first.

## Notes

- Security advisor `function_search_path_mutable` for `public.sync_pull_page` is remediated.
- Remaining accepted security advisor: `auth_leaked_password_protection`.
