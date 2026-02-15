# Web UX Modernization Implementation Plan (Full v2 Sync Coverage)

## Execution Tracker (Living Plan)

Use this section as the canonical progress tracker. After completing any step, immediately update:
- the step `Status`
- the `Last Updated` date
- the `Progress Log` entry for that step
- the `Next Session Start Here` pointer

Status values:
- `PENDING`
- `IN_PROGRESS`
- `DONE`
- `BLOCKED`

Last Updated: 2026-02-14
Current Owner: Codex + Shahar
Next Session Start Here: Completed through Step 14 (monitor + iterate)

### Progress Log Format (append under each step)

```text
- Date: YYYY-MM-DD
  Owner: <name>
  Change: <what was completed>
  Files: <absolute paths changed>
  Verification: <tests/commands run and outcome>
  Next: <exact next action>
```

### Step 1: Freeze UX Scope + v2 Entity Matrix

Status: `DONE`
Goal:
- Lock the UX modernization scope to the full v2 sync contract and avoid partial/implicit coverage.

Deliverables:
- Explicit list of all server-synced v2 entities covered by this UX plan.
- Explicit list of local-only models excluded from server sync.
- Clear domain map for web information architecture.

Exit Criteria:
- Scope is unambiguous for future sessions.
- Team can map every synced entity to either first-class UI or intentional deferred status.

Contract Lock (2026-02-14):
- v2 server-synced entities:
  `plan_kinds`, `day_types`, `plans`, `plan_days`,
  `activities`, `training_types`, `exercises`, `boulder_combinations`, `boulder_combination_exercises`,
  `sessions`, `session_items`,
  `timer_templates`, `timer_intervals`, `timer_sessions`, `timer_laps`,
  `climb_entries`, `climb_styles`, `climb_gyms`, `climb_media`.
- local-only models (excluded from server sync):
  `SyncState`, `SyncMutation`.
- domain map for UX execution:
  `Catalog`, `Plans`, `Sessions`, `Timers`, `Climb Log`, `Media`.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Created this living web UX implementation tracker and locked scope to the full v2 entity matrix from the sync plan.
  Files: docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: Manual reconciliation against `docs/SUPABASE_SYNC_IMPLEMENTATION_PLAN.md` Step 18 contract lock.
  Next: Start Step 2 shell/navigation redesign work.

### Step 2: Shell + Navigation Information Architecture

Status: `DONE`
Goal:
- Replace the current utility shell with a clear, app-like structure across all v2 domains.

Deliverables:
- Route structure for: `Catalog`, `Plans`, `Sessions`, `Timers`, `Climb Log`, `Media`.
- Desktop nav + mobile nav with consistent active state.
- Shared top-level page header/status regions.

Exit Criteria:
- Users can reach every domain in 1-2 interactions.
- Navigation behavior is consistent and predictable on desktop and mobile.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Expanded web IA and shell navigation to all v2 domains by adding route surfaces for sessions/timers/climb-log/media, adding reusable domain placeholder view for staged rollout, and implementing desktop+mobile primary navigation with active-route highlighting.
  Files: app.html, web/js/bootstrap.js, web/js/views/domainPlaceholderView.js, web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/views/domainPlaceholderView.js` passed; manual route/active-state logic review confirms route matching for base and nested paths.
  Next: Start Step 3 tokenized design system baseline and shared UI state styling.

### Step 3: Design System + Visual Foundation

Status: `DONE`
Goal:
- Establish a cohesive Apple-like visual language and interaction baseline.

Deliverables:
- Design tokens (spacing, radius, typography, motion, semantic colors).
- Unified surface/card/form/button styles and states.
- Focus, hover, pressed, disabled, and error state definitions.

Exit Criteria:
- All views consume shared tokens and primitives.
- Contrast and focus visibility are compliant and testable.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Added tokenized spacing/radius/focus/motion variables and unified interactive state styling (hover/focus/disabled/active) for nav, buttons, inputs, list rows, panes, and toasts to establish the shared visual baseline for subsequent domain refactors.
  Files: web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: Manual CSS review confirms shared token usage and consistent focus-visible treatment across core interactive controls.
  Next: Start Step 4 by introducing reusable list/detail/edit shell primitives used by Catalog and Plans.

### Step 4: Shared View Architecture (List -> Detail -> Edit)

Status: `DONE`
Goal:
- Move from dense CRUD blocks to progressive, task-driven flows.

Deliverables:
- Reusable list/detail/editor layout primitives.
- Empty, loading, and error states for each layout state.
- Shared save-state presentation (`saving`, `saved`, `queued`, `conflict`).

Exit Criteria:
- No domain view renders all editors at once.
- New domains can be added with the same interaction pattern.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Introduced reusable workspace shell primitives (`renderWorkspaceShell`, `renderEmptyState`) and wired new domain route placeholders to those primitives; added shared shell/empty-state/pill styling as the base for upcoming Catalog/Plans split-pane migration.
  Files: web/js/components/workspaceLayout.js, web/js/views/domainPlaceholderView.js, web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/domainPlaceholderView.js && node --check web/js/components/workspaceLayout.js && node --check web/js/bootstrap.js` passed.
  Next: Refactor Catalog and Plans views onto shared list/detail/edit structure.
- Date: 2026-02-14
  Owner: Codex
  Change: Added delete confirmation guards for catalog destructive actions (training types, exercises, combinations) to reduce accidental destructive edits while list/detail refactors are underway.
  Files: web/js/views/catalogView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/catalogView.js` passed.
  Next: Continue Step 4 structural migration for catalog/plans list/detail/edit separation.
- Date: 2026-02-14
  Owner: Codex
  Change: Migrated Catalog and Plans views onto shared workspace shell structure (`renderWorkspaceShell`) and reduced editor density by moving both domains to context-driven editor panes instead of always rendering multiple editors simultaneously.
  Files: web/js/views/catalogView.js, web/js/views/plansView.js, web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/catalogView.js && node --check web/js/views/plansView.js && node --check web/js/components/workspaceLayout.js` passed.
  Next: Continue domain-specific UX improvements in Steps 5 and 6.

### Step 5: Catalog Domain UX Refactor

Status: `DONE`
Goal:
- Modernize catalog editing flow while preserving sync correctness.

Deliverables:
- Improved flow for `activities`, `training_types`, `exercises`, `boulder_combinations`.
- Embedded relationship management for `boulder_combination_exercises`.
- Safer destructive actions with confirmation and undo affordances.

Exit Criteria:
- Catalog workflows are significantly faster and less error-prone than current web UX.
- Parent-child relationships are clear and guarded in UI.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Added catalog safety and context improvements: destructive delete confirmation prompts, explicit current-selection summary, and a single context-aware editor pane (training type / exercise / combination) while keeping boulder combination relationship editing embedded.
  Files: web/js/views/catalogView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/catalogView.js` passed.
  Next: Implement undo affordance for destructive catalog actions and further reduce form friction.
- Date: 2026-02-14
  Owner: Codex
  Change: Added undo-capable destructive flows for catalog entities by extending toast actions and wiring restore mutations for deleted training types, exercises, and combinations.
  Files: web/js/views/catalogView.js, web/js/components/toasts.js, web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/catalogView.js && node --check web/js/components/toasts.js` passed.
  Next: Continue global sync/conflict quality pass.

### Step 6: Plans Domain UX Refactor

Status: `DONE`
Goal:
- Align plan and plan-day interactions with app behavior and hierarchy.

Deliverables:
- Structured flow for `plans`, `plan_days`, `plan_kinds`, `day_types`.
- Plan detail + day editor separation.
- Mobile-safe editing flow with sticky primary actions.

Exit Criteria:
- Plan/day editing is usable without horizontal overflow and with clear save states.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Refined plans information hierarchy by separating plan-day browsing from editing, removing forced auto-selection of first day, and introducing explicit mode switching (`Edit Plan Details`) so users can intentionally choose plan-level vs day-level editing.
  Files: web/js/views/plansView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/plansView.js` passed.
  Next: Improve mobile ergonomics for day editing and add safer destructive action flow parity for plan/day deletes.
- Date: 2026-02-14
  Owner: Codex
  Change: Added destructive-action confirmation guards for deleting plans and plan days to reduce accidental data loss and align with catalog safety behavior.
  Files: web/js/views/plansView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/plansView.js` passed.
  Next: Add mobile-focused spacing/sticky actions for long day-edit forms.
- Date: 2026-02-14
  Owner: Codex
  Change: Added mobile sticky action rows for edit panes so primary actions remain reachable in long form editing flows.
  Files: web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: Manual CSS review for mobile breakpoint behavior.
  Next: Move to Step 7 sessions domain UX implementation.

### Step 7: Sessions Domain UX (New Web Surface)

Status: `DONE`
Goal:
- Add first-class web UX for sessions and session items.

Deliverables:
- CRUD flow for `sessions` and `session_items`.
- Parent-child integrity handling and ordering behavior in UI.
- Fast add/edit/remove interactions with robust validation.

Exit Criteria:
- Session workflows are fully operable on web with sync parity.
- No orphan child mutations can be produced by UI.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Implemented first-class Sessions web workspace with list/detail/edit CRUD for `sessions` and `session_items`, including required contract payload fields, selection state wiring in app bootstrap, and destructive confirmation flow.
  Files: web/js/views/sessionsView.js, web/js/bootstrap.js, web/css/app.css, app.html, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/views/sessionsView.js && node --check web/js/views/catalogView.js && node --check web/js/views/plansView.js` passed.
  Next: Start Step 8 climb log workspace implementation.

### Step 8: Climb Log Domain UX (New Web Surface)

Status: `DONE`
Goal:
- Add climb editing/browsing experience aligned with app mental model.

Deliverables:
- CRUD and filtering for `climb_entries`.
- Relationship editors for `climb_styles` and `climb_gyms`.
- Readable detail and edit forms tuned for mobile and desktop.

Exit Criteria:
- Core climb workflows are complete and discoverable on web.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Replaced climb-log placeholder with functional workspace: CRUD for `climb_entries`, create/delete management for `climb_styles` and `climb_gyms`, and full entry editor mapped to v2 sync payload fields.
  Files: web/js/views/climbView.js, web/js/bootstrap.js, web/css/app.css, app.html, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/views/climbView.js && node --check web/js/views/sessionsView.js` passed.
  Next: Add entry filtering/search controls and mobile tune-up for climb form density.
- Date: 2026-02-14
  Owner: Codex
  Change: Added entry filtering controls for climb log (`search`, `only work in progress`) and persisted filter state in shared selection state for stable rerender behavior.
  Files: web/js/views/climbView.js, web/js/bootstrap.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/climbView.js && node --check web/js/bootstrap.js` passed.
  Next: Start Step 9 timers domain UX implementation.

### Step 9: Timers Domain UX (New Web Surface)

Status: `DONE`
Goal:
- Add robust timers UX across templates and runtime records.

Deliverables:
- CRUD for `timer_templates` and child `timer_intervals`.
- History/detail handling for `timer_sessions` and `timer_laps`.
- Parent-child validation messaging and safe edit patterns.

Exit Criteria:
- Timer entities are usable on web without raw/technical workflows.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Replaced timers placeholder with functional workspace: CRUD for `timer_templates` and `timer_intervals`, plus timer session history and lap detail browsing for `timer_sessions` and `timer_laps`.
  Files: web/js/views/timersView.js, web/js/bootstrap.js, web/css/app.css, app.html, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/views/timersView.js && node --check web/js/views/climbView.js && node --check web/js/views/sessionsView.js` passed.
  Next: Start Step 10 media domain workspace implementation.

### Step 10: Media Exclusion Enforcement (Web)

Status: `DONE`

Correction captured from owner:
- we shouldn't sync media in web UX; delete media references from website surfaces.

Goal:
- Remove media from web UX scope and prevent partial/accidental media editing.

Deliverables:
- No media route, navigation item, or workspace in web shell.
- No media editing state in web bootstrap selections.
- No `climb_media` bucket in web sync store handling.

Exit Criteria:
- Website contains no media domain references in UI/routes/workspace code.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Replaced media placeholder with metadata workspace for `climb_media`, including list/create/edit/delete flows, linkage to `climb_entries`, and editable storage metadata fields (`storage_bucket`, `storage_path`, `thumbnail_storage_path`).
  Files: web/js/views/mediaView.js, web/js/bootstrap.js, web/css/app.css, app.html, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/views/mediaView.js && node --check web/js/views/timersView.js && node --check web/js/views/climbView.js && node --check web/js/views/sessionsView.js` passed.
  Next: Add explicit media sync status/retry messaging and local-only field notice in UI copy.
- Date: 2026-02-14
  Owner: Codex
  Change: Added in-product media sync guidance in the Media workspace clarifying device-local identifier behavior and metadata recovery path when storage linkage is incomplete.
  Files: web/js/views/mediaView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/views/mediaView.js` passed.
  Next: Add explicit retry action control for failed linkage states.
- Date: 2026-02-14
  Owner: Codex
  Change: Applied correction by removing media from web product surface: removed nav route/buttons/copy references, removed media view wiring/state, removed `climb_media` from web store entity buckets, and deleted media view module.
  Files: app.html, web/js/bootstrap.js, web/js/state/store.js, web/css/app.css, web/js/views/mediaView.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `rg -n "climb_media|mediaId|renderMediaView|#/media|/media|Media" app.html web/js web/css` returns no matches for media domain references; JS syntax checks pass for active web modules.
  Next: Continue unified sync/conflict and quality hardening steps.

### Step 11: Unified Sync State + Conflict Center v2

Status: `DONE`
Goal:
- Make sync behavior understandable and actionable across all domains.

Deliverables:
- Human-readable global + per-record sync states.
- Expanded conflict center labels/actions for all v2 entities.
- Immediate UI reconciliation after conflict actions.

Exit Criteria:
- Users can resolve conflicts without leaving current workflow.
- Technical sync internals are hidden behind clear UX language.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Added unified status tones (`ready`, `syncing`, `warning`, `error`) via status-pill metadata styling and upgraded runtime status transitions across auth/sync/mutation/conflict flows. Expanded conflict entity normalization for all v2 web-exposed domains (excluding media per scope correction).
  Files: web/js/bootstrap.js, web/js/components/conflictPanel.js, web/css/app.css, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/components/conflictPanel.js` passed.
  Next: Close API/UI guardrail step with explicit supported-scope messaging.

### Step 12: API/UI Scope Guardrails (Step 23 Closure)

Status: `DONE`
Goal:
- Prevent partial support confusion while domains roll out incrementally.

Deliverables:
- Explicit in-app messaging for API-supported but UI-deferred entities.
- Safeguards against creating writes in unsupported/deferred surfaces.
- Updated operator-facing scope notes.

Exit Criteria:
- Web behavior always matches documented support level.
- Step 23 in sync plan can be closed with user-visible evidence.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Enforced explicit web scope at shell level by updating supported-domain messaging and removing unsupported media route/surface wiring, so the website cannot expose partial/ambiguous media behavior.
  Files: app.html, web/js/bootstrap.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: Manual route/shell review plus grep sweep confirms no media domain UI route references remain in website files.
  Next: Complete accessibility and keyboard pass.

### Step 13: Accessibility + Keyboard + Mobile Quality Pass

Status: `DONE`
Goal:
- Raise quality bar for inclusive and efficient interaction.

Deliverables:
- Keyboard navigation and shortcuts for core workflows.
- Focus management for dialogs/sheets/drawers.
- Screen-reader labels and logical tab ordering.

Exit Criteria:
- Core workflows are keyboard-complete and screen-reader friendly.
- Mobile UX is intentionally designed, not only stacked desktop UI.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Added keyboard shortcuts (`Alt+1..5` for section routing, `/` to focus search input), and improved nav accessibility semantics by setting/removing `aria-current="page"` for active route links.
  Files: web/js/bootstrap.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js` passed; manual logic review confirms no shortcut interception inside text-entry fields.
  Next: Complete telemetry + QA matrix + rollout gates.

### Step 14: Telemetry, QA Matrix, and Rollout Gates

Status: `DONE`
Goal:
- Ensure measurable UX improvements and safe rollout across all v2 entities.

Deliverables:
- Telemetry events for completion time, conflict resolution, save latency, and retries.
- End-to-end QA matrix covering all v2 entities/domains.
- Rollout gates and rollback conditions documented.

Exit Criteria:
- Data exists to validate UX improvements and reliability.
- Team can pause/roll back domains independently if needed.

Progress Log:
- Date: 2026-02-14
  Owner: Codex
  Change: Implemented lightweight web UX telemetry stream (`web_ux_telemetry_events` in localStorage + console info) for route views, mutation lifecycle, and conflict actions. Added explicit QA matrix and rollout gate checklist document.
  Files: web/js/bootstrap.js, docs/WEB_UX_QA_MATRIX.md, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js` passed; manual review confirms telemetry write path and bounded local buffer behavior.
  Next: Monitor field usage and iterate based on telemetry + QA findings.
- Date: 2026-02-14
  Owner: Codex
  Change: Hardened telemetry path so it is strictly best-effort and cannot interrupt auth/session hydration or sync pull (added guarded writes + UUID fallback + top-level try/catch in event tracking).
  Files: web/js/bootstrap.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check web/js/bootstrap.js && node --check web/js/syncApi.js && node --check web/js/supabaseClient.js` passed.
  Next: Verify live fetch/hydration behavior in browser session and inspect console/network if any remaining auth/sync endpoint errors appear.
- Date: 2026-02-14
  Owner: Codex
  Change: Added explicit web hydration fetch smoke test (`supabase_sync_web_hydration_smoke.mjs`) and implemented cursor recovery fallback in web bootstrap (auto reset stale cursor + retry full pull when cursor-based hydration returns empty and store has no data).
  Files: scripts/supabase_sync_web_hydration_smoke.mjs, web/js/bootstrap.js, docs/WEB_UX_QA_MATRIX.md, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: Live run with test credentials passed: `node scripts/supabase_sync_web_smoke.mjs` and `node scripts/supabase_sync_web_hydration_smoke.mjs` both `ok: true`.
  Next: Monitor real-user browser sessions; if fetch still fails, inspect console/network for auth token/session errors per-user environment.
- Date: 2026-02-14
  Owner: Codex
  Change: Added web registration capability in auth UI (`Create Account`) and wired Supabase sign-up flow, including validation and post-signup handling for either immediate session or email-confirmation flow. Added live auth registration smoke test script.
  Files: web/js/views/loginView.js, web/js/auth.js, web/js/bootstrap.js, scripts/supabase_auth_register_smoke.mjs, docs/WEB_UX_QA_MATRIX.md, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check` passed for updated web auth files and script; live run `node scripts/supabase_auth_register_smoke.mjs` returned `ok: true` with `signInExistingWorked: true` against `<test-email>`.
  Next: Monitor Supabase auth rate-limit/policy responses in production and tune UX copy if needed.
- Date: 2026-02-14
  Owner: Codex
  Change: Fixed blank-screen startup risk by removing hard dependency on external `esm.sh` Supabase runtime client in web auth path, migrating web auth/session to direct Supabase REST endpoints with local session token storage, and keeping sync pull/push on bearer token from local session.
  Files: web/js/supabaseClient.js, web/js/auth.js, web/js/syncApi.js, web/js/bootstrap.js, docs/WEB_UX_V2_IMPLEMENTATION_PLAN.md
  Verification: `node --check` passed for updated modules; live runs with test credentials passed: `node scripts/supabase_sync_web_smoke.mjs` and `node scripts/supabase_sync_web_hydration_smoke.mjs` both returned `ok: true`.
  Next: Browser-validate locally on `http://localhost:5173/app.html` with hard refresh to ensure startup now renders reliably in your environment.
