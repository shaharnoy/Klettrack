# Supabase Sync Rollout Checklist (v2 Full Model)

## Stage 1: Internal
- Enable sync for internal test accounts only.
- Run live contract tests and web smoke tests.
- Verify no cross-tenant visibility issues.

## Stage 2: Beta A (Plans)
- Keep catalog writes limited.
- Monitor conflicts and failed pushes daily.
- Confirm kill switch rollback works in <5 minutes.

## Stage 3: Beta B (Catalog + Plans)
- Enable catalog write paths for beta cohort.
- Run scale validation script with cohort-like load.
- Confirm support runbooks are available to on-call.

## Stage 4: GA
- Turn on rollout flag by default for signed-in users.
- Keep kill switch available.
- Publish known limitations and support path.

## Stage 5: v2 Entities Ramp
- Enable sessions/timers/climbs sync for internal cohort first.
- Run contract + scale scripts that include `session_items`, `timer_laps`, and `climb_entries`.
- Confirm parent-link failures are rejected safely (`invalid_parent_reference`).
- Validate media runbook with one intentionally missing storage object.

## Exit criteria
- No critical data-loss incidents.
- Conflict resolution works without app restart.
- Production monitoring and alert ownership is active.
- v2 entity contract checks pass in live environment.
