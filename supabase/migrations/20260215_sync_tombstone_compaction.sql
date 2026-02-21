-- Tombstone compaction helper for sync tables.
create or replace function public.sync_compact_tombstones(
  p_retention interval default interval '30 days'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  cutoff timestamptz := now() - p_retention;
  deleted_total bigint := 0;
  deleted_rows bigint := 0;
  table_name text;
  targets text[] := array[
    'plan_kinds',
    'day_types',
    'plans',
    'plan_days',
    'activities',
    'training_types',
    'exercises',
    'boulder_combinations',
    'boulder_combination_exercises',
    'sessions',
    'session_items',
    'timer_templates',
    'timer_intervals',
    'timer_sessions',
    'timer_laps',
    'climb_entries',
    'climb_styles',
    'climb_gyms'
  ];
  per_table jsonb := '{}'::jsonb;
begin
  foreach table_name in array targets loop
    execute format(
      'delete from public.%I where is_deleted = true and updated_at_server < $1',
      table_name
    )
    using cutoff;

    get diagnostics deleted_rows = row_count;
    deleted_total := deleted_total + deleted_rows;
    per_table := per_table || jsonb_build_object(table_name, deleted_rows);
  end loop;

  return jsonb_build_object(
    'retention', p_retention::text,
    'cutoff', cutoff,
    'deleted_total', deleted_total,
    'by_table', per_table
  );
end;
$$;

revoke all on function public.sync_compact_tombstones(interval) from public;
revoke all on function public.sync_compact_tombstones(interval) from anon;
revoke all on function public.sync_compact_tombstones(interval) from authenticated;
grant execute on function public.sync_compact_tombstones(interval) to service_role;
