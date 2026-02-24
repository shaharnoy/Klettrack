# Sync SQL Verification Queries

Use these queries to verify sync churn and span issues for a single account.
Replace `<OWNER_UUID>` before running.

## 1) Per-entity span by owner

```sql
with target as (
  select '<OWNER_UUID>'::uuid as owner_id
),
rows as (
  select 'plan_kinds' as entity, created_at, updated_at_server from public.plan_kinds p, target t where p.owner_id = t.owner_id
  union all select 'day_types', created_at, updated_at_server from public.day_types p, target t where p.owner_id = t.owner_id
  union all select 'plans', created_at, updated_at_server from public.plans p, target t where p.owner_id = t.owner_id
  union all select 'plan_days', created_at, updated_at_server from public.plan_days p, target t where p.owner_id = t.owner_id
  union all select 'activities', created_at, updated_at_server from public.activities p, target t where p.owner_id = t.owner_id
  union all select 'training_types', created_at, updated_at_server from public.training_types p, target t where p.owner_id = t.owner_id
  union all select 'exercises', created_at, updated_at_server from public.exercises p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combinations', created_at, updated_at_server from public.boulder_combinations p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combination_exercises', created_at, updated_at_server from public.boulder_combination_exercises p, target t where p.owner_id = t.owner_id
  union all select 'sessions', created_at, updated_at_server from public.sessions p, target t where p.owner_id = t.owner_id
  union all select 'session_items', created_at, updated_at_server from public.session_items p, target t where p.owner_id = t.owner_id
  union all select 'timer_templates', created_at, updated_at_server from public.timer_templates p, target t where p.owner_id = t.owner_id
  union all select 'timer_intervals', created_at, updated_at_server from public.timer_intervals p, target t where p.owner_id = t.owner_id
  union all select 'timer_sessions', created_at, updated_at_server from public.timer_sessions p, target t where p.owner_id = t.owner_id
  union all select 'timer_laps', created_at, updated_at_server from public.timer_laps p, target t where p.owner_id = t.owner_id
  union all select 'climb_entries', created_at, updated_at_server from public.climb_entries p, target t where p.owner_id = t.owner_id
  union all select 'climb_styles', created_at, updated_at_server from public.climb_styles p, target t where p.owner_id = t.owner_id
  union all select 'climb_gyms', created_at, updated_at_server from public.climb_gyms p, target t where p.owner_id = t.owner_id
)
select
  entity,
  count(*) as row_count,
  min(created_at) as min_created_at,
  max(created_at) as max_created_at,
  max(created_at) - min(created_at) as created_span,
  min(updated_at_server) as min_updated_at_server,
  max(updated_at_server) as max_updated_at_server,
  max(updated_at_server) - min(updated_at_server) as updated_at_server_span
from rows
group by entity
order by row_count desc, entity;
```

## 2) Version distribution by entity

```sql
with target as (
  select '<OWNER_UUID>'::uuid as owner_id
),
versions as (
  select 'plan_kinds' as entity, version from public.plan_kinds p, target t where p.owner_id = t.owner_id
  union all select 'day_types', version from public.day_types p, target t where p.owner_id = t.owner_id
  union all select 'plans', version from public.plans p, target t where p.owner_id = t.owner_id
  union all select 'plan_days', version from public.plan_days p, target t where p.owner_id = t.owner_id
  union all select 'activities', version from public.activities p, target t where p.owner_id = t.owner_id
  union all select 'training_types', version from public.training_types p, target t where p.owner_id = t.owner_id
  union all select 'exercises', version from public.exercises p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combinations', version from public.boulder_combinations p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combination_exercises', version from public.boulder_combination_exercises p, target t where p.owner_id = t.owner_id
  union all select 'sessions', version from public.sessions p, target t where p.owner_id = t.owner_id
  union all select 'session_items', version from public.session_items p, target t where p.owner_id = t.owner_id
  union all select 'timer_templates', version from public.timer_templates p, target t where p.owner_id = t.owner_id
  union all select 'timer_intervals', version from public.timer_intervals p, target t where p.owner_id = t.owner_id
  union all select 'timer_sessions', version from public.timer_sessions p, target t where p.owner_id = t.owner_id
  union all select 'timer_laps', version from public.timer_laps p, target t where p.owner_id = t.owner_id
  union all select 'climb_entries', version from public.climb_entries p, target t where p.owner_id = t.owner_id
  union all select 'climb_styles', version from public.climb_styles p, target t where p.owner_id = t.owner_id
  union all select 'climb_gyms', version from public.climb_gyms p, target t where p.owner_id = t.owner_id
)
select entity, version, count(*) as rows_at_version
from versions
group by entity, version
order by entity, version desc;
```

## 3) Repeated-update detector (server churn vs client timestamp)

```sql
with target as (
  select '<OWNER_UUID>'::uuid as owner_id
),
rows as (
  select 'plan_kinds'::text as entity, id, version, updated_at_client, updated_at_server from public.plan_kinds p, target t where p.owner_id = t.owner_id
  union all select 'day_types', id, version, updated_at_client, updated_at_server from public.day_types p, target t where p.owner_id = t.owner_id
  union all select 'plans', id, version, updated_at_client, updated_at_server from public.plans p, target t where p.owner_id = t.owner_id
  union all select 'plan_days', id, version, updated_at_client, updated_at_server from public.plan_days p, target t where p.owner_id = t.owner_id
  union all select 'activities', id, version, updated_at_client, updated_at_server from public.activities p, target t where p.owner_id = t.owner_id
  union all select 'training_types', id, version, updated_at_client, updated_at_server from public.training_types p, target t where p.owner_id = t.owner_id
  union all select 'exercises', id, version, updated_at_client, updated_at_server from public.exercises p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combinations', id, version, updated_at_client, updated_at_server from public.boulder_combinations p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combination_exercises', id, version, updated_at_client, updated_at_server from public.boulder_combination_exercises p, target t where p.owner_id = t.owner_id
  union all select 'sessions', id, version, updated_at_client, updated_at_server from public.sessions p, target t where p.owner_id = t.owner_id
  union all select 'session_items', id, version, updated_at_client, updated_at_server from public.session_items p, target t where p.owner_id = t.owner_id
  union all select 'timer_templates', id, version, updated_at_client, updated_at_server from public.timer_templates p, target t where p.owner_id = t.owner_id
  union all select 'timer_intervals', id, version, updated_at_client, updated_at_server from public.timer_intervals p, target t where p.owner_id = t.owner_id
  union all select 'timer_sessions', id, version, updated_at_client, updated_at_server from public.timer_sessions p, target t where p.owner_id = t.owner_id
  union all select 'timer_laps', id, version, updated_at_client, updated_at_server from public.timer_laps p, target t where p.owner_id = t.owner_id
  union all select 'climb_entries', id, version, updated_at_client, updated_at_server from public.climb_entries p, target t where p.owner_id = t.owner_id
  union all select 'climb_styles', id, version, updated_at_client, updated_at_server from public.climb_styles p, target t where p.owner_id = t.owner_id
  union all select 'climb_gyms', id, version, updated_at_client, updated_at_server from public.climb_gyms p, target t where p.owner_id = t.owner_id
)
select
  entity,
  id,
  version,
  updated_at_client,
  updated_at_server,
  (updated_at_server - updated_at_client) as server_minus_client_lag
from rows
where updated_at_client is not null
  and version >= 2
  and updated_at_server > updated_at_client + interval '5 minutes'
order by server_minus_client_lag desc
limit 200;
```

## 4) Count rows touched >1x in rolling windows

```sql
with target as (
  select '<OWNER_UUID>'::uuid as owner_id
),
rows as (
  select 'plan_kinds'::text as entity, version, updated_at_server from public.plan_kinds p, target t where p.owner_id = t.owner_id
  union all select 'day_types', version, updated_at_server from public.day_types p, target t where p.owner_id = t.owner_id
  union all select 'plans', version, updated_at_server from public.plans p, target t where p.owner_id = t.owner_id
  union all select 'plan_days', version, updated_at_server from public.plan_days p, target t where p.owner_id = t.owner_id
  union all select 'activities', version, updated_at_server from public.activities p, target t where p.owner_id = t.owner_id
  union all select 'training_types', version, updated_at_server from public.training_types p, target t where p.owner_id = t.owner_id
  union all select 'exercises', version, updated_at_server from public.exercises p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combinations', version, updated_at_server from public.boulder_combinations p, target t where p.owner_id = t.owner_id
  union all select 'boulder_combination_exercises', version, updated_at_server from public.boulder_combination_exercises p, target t where p.owner_id = t.owner_id
  union all select 'sessions', version, updated_at_server from public.sessions p, target t where p.owner_id = t.owner_id
  union all select 'session_items', version, updated_at_server from public.session_items p, target t where p.owner_id = t.owner_id
  union all select 'timer_templates', version, updated_at_server from public.timer_templates p, target t where p.owner_id = t.owner_id
  union all select 'timer_intervals', version, updated_at_server from public.timer_intervals p, target t where p.owner_id = t.owner_id
  union all select 'timer_sessions', version, updated_at_server from public.timer_sessions p, target t where p.owner_id = t.owner_id
  union all select 'timer_laps', version, updated_at_server from public.timer_laps p, target t where p.owner_id = t.owner_id
  union all select 'climb_entries', version, updated_at_server from public.climb_entries p, target t where p.owner_id = t.owner_id
  union all select 'climb_styles', version, updated_at_server from public.climb_styles p, target t where p.owner_id = t.owner_id
  union all select 'climb_gyms', version, updated_at_server from public.climb_gyms p, target t where p.owner_id = t.owner_id
)
select
  entity,
  count(*) filter (where version > 1) as rows_touched_more_than_once,
  count(*) filter (where version > 1 and updated_at_server >= now() - interval '24 hours') as rows_touched_more_than_once_last_24h,
  count(*) filter (where version > 1 and updated_at_server >= now() - interval '7 days') as rows_touched_more_than_once_last_7d,
  count(*) as total_rows
from rows
group by entity
having count(*) > 0
order by rows_touched_more_than_once_last_24h desc, rows_touched_more_than_once desc, entity;
```
