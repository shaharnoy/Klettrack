# Supabase Sync Advisor Maintenance

Date: February 15, 2026

## Security advisor snapshot

- `auth_leaked_password_protection` (`WARN`) remains open by explicit product decision (`4B`).
- `function_search_path_mutable` is remediated.

## Performance advisor snapshot

Current `INFO` findings are `unused_index` lints on:

- `public.session_items.session_items_session_id_idx`
- `public.timer_intervals.timer_intervals_template_id_idx`
- `public.timer_sessions.timer_sessions_template_id_idx`
- `public.timer_sessions.timer_sessions_plan_day_id_idx`
- `public.timer_laps.timer_laps_session_id_idx`
- `public.climb_media.climb_media_entry_id_idx`
- `public.plan_days.plan_days_day_type_id_idx`
- `public.plans.plans_kind_id_idx`
- `public.plan_days.plan_days_plan_id_idx`
- `public.boulder_combinations.boulder_combinations_training_type_id_idx`
- `public.boulder_combination_exercises.boulder_combination_exercises_combo_id_idx`
- `public.boulder_combination_exercises.boulder_combination_exercises_exercise_id_idx`

## Decision and rationale

- Decision: keep all currently flagged unused indexes in place for now.
- Rationale: these are FK/supporting path indexes used by sync domain reads and writes; production workload has not yet reached steady-state enough to safely remove them.
- Evidence: live `pg_stat_user_indexes` snapshot shows these indexes currently at `idx_scan = 0`, but owner/cursor sync indexes are actively used. We will only remove FK/supporting indexes after observing stable production query patterns over a longer period.

## CI guardrail

- Added static CI check to prevent RLS regressions:
  - script: `scripts/check_sync_rls_coverage.sh`
  - workflow: `.github/workflows/supabase-rls-check.yml`
- This gate verifies every sync table has:
  - `alter table public.<table> enable row level security;`
  - at least one `create policy ... on public.<table>`

