-- Add sync tables to Supabase Realtime publication (idempotent).
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'plans',
    'plan_days',
    'plan_kinds',
    'day_types',
    'activities',
    'training_types',
    'exercises',
    'boulder_combinations',
    'boulder_combination_exercises'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end
$$;
