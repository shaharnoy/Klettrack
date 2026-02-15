# Web UX v2 QA Matrix

Last Updated: 2026-02-14
Owner: Codex + Shahar

## Validation Commands

Run after each web UX change:

```bash
node --check web/js/bootstrap.js
node --check web/js/views/catalogView.js
node --check web/js/views/plansView.js
node --check web/js/views/sessionsView.js
node --check web/js/views/climbView.js
node --check web/js/views/timersView.js
node --check web/js/components/conflictPanel.js
node --check web/js/components/toasts.js
```

Live Supabase fetch regression check:

```bash
SUPABASE_URL="<project-url>" \
SUPABASE_PUBLISHABLE_KEY="<publishable-key>" \
SUPABASE_TEST_EMAIL="<email>" \
SUPABASE_TEST_PASSWORD="<password>" \
node scripts/supabase_sync_web_hydration_smoke.mjs
```

Live Supabase registration/auth smoke:

```bash
SUPABASE_URL="<project-url>" \
SUPABASE_PUBLISHABLE_KEY="<publishable-key>" \
SUPABASE_TEST_EMAIL="<email>" \
SUPABASE_TEST_PASSWORD="<password>" \
node scripts/supabase_auth_register_smoke.mjs
```

Live Supabase forgot-password smoke:

```bash
SUPABASE_URL="<project-url>" \
SUPABASE_PUBLISHABLE_KEY="<publishable-key>" \
SUPABASE_TEST_EMAIL="<email>" \
node scripts/supabase_auth_forgot_password_smoke.mjs
```

## Manual Flow Checklist

### Catalog
- Create activity, training type, exercise, and combination.
- Delete each entity and verify `Undo` restores it.
- Validate single context editor switches between training type, exercise, and combination.

### Plans
- Create plan and plan day.
- Edit plan details and day details in separate modes.
- Delete plan/day and verify `Undo` restores record.

### Sessions
- Create session and session item.
- Edit session item metrics.
- Delete session/session item and confirm guard dialog behavior.

### Timers
- Create template and interval.
- Edit interval ordering and template repeat config.
- Open timer sessions list and verify lap rendering for selected session.

### Climb Log
- Create style and gym metadata.
- Create climb entry using required fields.
- Filter entries by text and WIP toggle.
- Edit and delete entry with guard dialog.

### Sync + Conflict
- Trigger a normal upsert and verify status transitions to `All changes synced`.
- Trigger a conflict and verify warning status with actionable conflict panel.
- Resolve `Keep Mine` and `Keep Server` paths and confirm post-resolution pull/render.

### Navigation + Accessibility
- Validate desktop + mobile nav route switching.
- Verify `aria-current="page"` updates on active nav links.
- Test keyboard shortcuts: `Alt+1..5` route switching and `/` focusing search input when present.

## Rollout Gates

- Gate 1: syntax checks all pass.
- Gate 2: manual flow checklist passes for all enabled domains.
- Gate 3: no regressions in auth route guarding and conflict resolution.
- Gate 4: telemetry events are emitted to `localStorage` key `web_ux_telemetry_events`.
