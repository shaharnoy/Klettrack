#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="${ROOT_DIR}/supabase/migrations"

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "migrations directory not found: ${MIGRATIONS_DIR}" >&2
  exit 1
fi

SYNC_TABLES=(
  "plan_kinds"
  "day_types"
  "plans"
  "plan_days"
  "activities"
  "training_types"
  "exercises"
  "boulder_combinations"
  "boulder_combination_exercises"
  "sessions"
  "session_items"
  "timer_templates"
  "timer_intervals"
  "timer_sessions"
  "timer_laps"
  "climb_entries"
  "climb_styles"
  "climb_gyms"
)

failures=0

echo "Checking RLS coverage for sync tables..."
for table in "${SYNC_TABLES[@]}"; do
  rls_pattern="alter table public\\.${table} enable row level security;"
  policy_pattern="create policy [^;]+ on public\\.${table}"

  if ! rg -q --glob '*.sql' "${rls_pattern}" "${MIGRATIONS_DIR}"; then
    echo "missing RLS enable statement for table public.${table}" >&2
    failures=$((failures + 1))
  fi

  if ! rg -q --glob '*.sql' "${policy_pattern}" "${MIGRATIONS_DIR}"; then
    echo "missing policy definition for table public.${table}" >&2
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "RLS coverage check failed with ${failures} issue(s)." >&2
  exit 1
fi

echo "RLS coverage check passed for ${#SYNC_TABLES[@]} sync tables."
