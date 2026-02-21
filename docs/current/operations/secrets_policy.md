# Secrets Policy

## Scope
- `docs/**/*.md`
- `scripts/**`
- `supabase/**`

## Rules
- Never commit live credentials, passwords, personal access tokens, or service role keys.
- Use placeholders in docs: `<project-url>`, `<publishable-key>`, `<test-email>`, `<test-password>`, `<access-token>`.
- Keep real values only in local environment variables (`.env`, shell exports, CI secrets).
- Treat any value committed to git history as compromised and rotate it.

## Allowed Public Values
- Supabase project URL and publishable/anon key may be public in runtime configuration.
- Documentation should still use placeholders to avoid accidental copy/paste of stale values.

## Markdown Security Check
Run before opening a PR:

```bash
rg -n "(SUPABASE_ACCESS_TOKEN=|SUPABASE_TEST_PASSWORD=|sb_secret_|service_role|Bearer\\s+[A-Za-z0-9._-]+)" --glob "**/*.md"
```

## Pre-PR Checklist
- [ ] No secrets in markdown/docs.
- [ ] No `supabase/.temp/*` artifacts are tracked.
- [ ] No `.DS_Store` files are tracked.
- [ ] Any exposed credentials were rotated.

## Rotation Requirement
- This repository update redacts previously documented values, but it cannot rotate remote credentials automatically.
- Project owner must rotate any credentials that appeared in git history (test user password, personal access token, service role key if ever exposed) before relying on them again.
