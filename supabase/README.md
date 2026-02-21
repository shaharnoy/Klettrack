# Supabase Backend

This folder is the source of truth for Supabase backend code.

## Structure
- Edge functions: `supabase/functions`
- SQL migrations: `supabase/migrations`

## Security notes
- Do not commit `supabase/.temp` artifacts.
- Do not commit live secrets in docs or scripts.
- Use placeholders in documentation and set real values through environment variables.

## Related docs
- `docs/current/supabase/sync_security_readiness.md`
- `docs/current/operations/supabase_sync_runbooks.md`
- `docs/current/operations/secrets_policy.md`
