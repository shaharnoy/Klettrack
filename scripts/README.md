# Scripts

Repository utility scripts are grouped by domain under `scripts/supabase`.

## Canonical paths

### Smoke tests
- `node scripts/supabase/smoke/sync_web_smoke.mjs`
- `node scripts/supabase/smoke/sync_web_hydration_smoke.mjs`
- `node scripts/supabase/smoke/data_manager_groups_smoke.mjs`
- `node scripts/supabase/smoke/auth_register_smoke.mjs`
- `node scripts/supabase/smoke/auth_forgot_password_smoke.mjs`
- `node scripts/supabase/smoke/auth_user_mgmt_smoke.mjs`

### Contract tests
- `node scripts/supabase/contract/sync_function_contract_tests.mjs`
- Includes a sync auth preflight that fails fast with a targeted diagnostic if `sync` is deployed with `verify_jwt=true` and returns `401 Invalid JWT`.

### Diagnostics
- `node scripts/supabase/diagnostics/sync_scale_validation.mjs`
- `node scripts/supabase/diagnostics/sync_latency_probe.mjs`
- `node scripts/supabase/diagnostics/token_shape.mjs`

`sync_scale_validation.mjs` supports CI thresholds via env vars:
- `SUPABASE_SCALE_MAX_ENTITY_SPAN_SECONDS`
- `SUPABASE_SCALE_MAX_CYCLE_DURATION_SECONDS`
- `SUPABASE_SCALE_MAX_NETWORK_RETRIES`
- `SUPABASE_SCALE_MAX_UNCHANGED_ROW_VERSION_BUMPS`

### Admin
- `scripts/supabase/admin/apply_auth_email_templates.sh`
- `scripts/supabase/admin/auth_email_templates_patch.json`

### Fixtures
- `scripts/supabase/fixtures/backups/`

## Compatibility wrappers

Legacy wrapper entrypoints were removed. Use only the canonical paths above.
