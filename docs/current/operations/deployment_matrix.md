# Deployment Matrix

## Website (static)
- Entrypoints:
  - `index.html`
  - `app.html`
  - `privacy.html`
  - `terms.html`
- Static assets:
  - `web/css`
  - `web/js`
  - `img`

## iOS app
- Project:
  - `ClimbingProgram.xcodeproj`
- Source:
  - `ClimbingProgram`
- Tests:
  - `ClimbingProgramTests`

## Supabase backend
- Migrations:
  - `supabase/migrations`
- Edge functions:
  - `supabase/functions`
- Local-only artifacts (ignored):
  - `supabase/.temp`

## Validation scripts
- Canonical scripts index:
  - `scripts/README.md`
