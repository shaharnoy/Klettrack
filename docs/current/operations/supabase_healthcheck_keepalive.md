# Supabase Healthcheck Keepalive

Use this to keep a free-tier Supabase project warm by pinging a lightweight Edge Function every day.

## 1) Deploy the `healthcheck` Edge Function

```bash
cd <repo-root>

# Authenticate and link to your Supabase project
supabase login
supabase link --project-ref "$PROJECT_REF"

# Optional but recommended: protect the endpoint with a shared token
supabase secrets set HEALTHCHECK_TOKEN="$SUPABASE_HEALTHCHECK_TOKEN"

# Deploy as a public endpoint (no JWT required)
supabase functions deploy healthcheck --no-verify-jwt
```

If you do not want token protection, skip the `supabase secrets set` command.

## 2) Verify manually

Healthcheck URL format:

```text
https://<PROJECT_REF>.functions.supabase.co/healthcheck
```

Ping without token:

```bash
curl --fail --show-error --silent "https://<PROJECT_REF>.functions.supabase.co/healthcheck"
```

Ping with token:

```bash
curl --fail --show-error --silent \
  -H "x-healthcheck-token: $SUPABASE_HEALTHCHECK_TOKEN" \
  "https://<PROJECT_REF>.functions.supabase.co/healthcheck"
```

## 3) Configure GitHub Action secrets

Add repository secrets:

- `SUPABASE_HEALTHCHECK_URL`: full URL to `/healthcheck`
- `SUPABASE_HEALTHCHECK_TOKEN`: optional; required only if you set `HEALTHCHECK_TOKEN` in Supabase

The workflow file is:

- `.github/workflows/supabase-healthcheck-ping.yml`

It runs daily and can also be triggered manually via `workflow_dispatch`.
