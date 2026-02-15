-- Consolidate sync pull into one RPC call to reduce per-request round trips.

begin;

create or replace function public.sync_pull_page(
  p_owner_id uuid,
  p_cursor text default null,
  p_limit integer default 200
)
returns table(changes jsonb, next_cursor text, has_more boolean)
language sql
stable
as $$
with params as (
  select
    greatest(1, least(coalesce(p_limit, 200), 500)) as page_limit,
    nullif(btrim(p_cursor), '') as cursor_text
),
cursor_parts as (
  select
    p.page_limit,
    p.cursor_text,
    case when p.cursor_text is null then null::timestamptz else split_part(p.cursor_text, '|', 1)::timestamptz end as cursor_ts,
    case when p.cursor_text is null then 'plan_kinds' else coalesce(nullif(split_part(p.cursor_text, '|', 2), ''), 'plan_kinds') end as cursor_entity,
    case when p.cursor_text is null then '' else coalesce(split_part(p.cursor_text, '|', 3), '') end as cursor_entity_id
  from params p
),
all_rows as (
  select 'activities'::text as entity, t.id::text as entity_id, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end as doc from public.activities t where t.owner_id = p_owner_id
  union all
  select 'boulder_combination_exercises', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.boulder_combination_exercises t where t.owner_id = p_owner_id
  union all
  select 'boulder_combinations', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.boulder_combinations t where t.owner_id = p_owner_id
  union all
  select 'climb_entries', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.climb_entries t where t.owner_id = p_owner_id
  union all
  select 'climb_gyms', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.climb_gyms t where t.owner_id = p_owner_id
  union all
  select 'climb_media', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.climb_media t where t.owner_id = p_owner_id
  union all
  select 'climb_styles', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.climb_styles t where t.owner_id = p_owner_id
  union all
  select 'day_types', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.day_types t where t.owner_id = p_owner_id
  union all
  select 'exercises', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.exercises t where t.owner_id = p_owner_id
  union all
  select 'plan_days', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.plan_days t where t.owner_id = p_owner_id
  union all
  select 'plan_kinds', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.plan_kinds t where t.owner_id = p_owner_id
  union all
  select 'plans', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.plans t where t.owner_id = p_owner_id
  union all
  select 'session_items', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.session_items t where t.owner_id = p_owner_id
  union all
  select 'sessions', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.sessions t where t.owner_id = p_owner_id
  union all
  select 'timer_intervals', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.timer_intervals t where t.owner_id = p_owner_id
  union all
  select 'timer_laps', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.timer_laps t where t.owner_id = p_owner_id
  union all
  select 'timer_sessions', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.timer_sessions t where t.owner_id = p_owner_id
  union all
  select 'timer_templates', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.timer_templates t where t.owner_id = p_owner_id
  union all
  select 'training_types', t.id::text, t.version, t.is_deleted, t.updated_at_server, case when t.is_deleted then null else to_jsonb(t) end from public.training_types t where t.owner_id = p_owner_id
),
filtered as (
  select r.*
  from all_rows r
  cross join cursor_parts c
  where c.cursor_text is null
     or r.updated_at_server > c.cursor_ts
     or (
       r.updated_at_server = c.cursor_ts
       and (
         r.entity > c.cursor_entity
         or (r.entity = c.cursor_entity and r.entity_id > c.cursor_entity_id)
       )
     )
),
ordered as (
  select * from filtered order by updated_at_server, entity, entity_id
),
windowed as (
  select o.*, row_number() over (order by o.updated_at_server, o.entity, o.entity_id) as rn
  from ordered o
),
page as (
  select w.*
  from windowed w
  cross join cursor_parts c
  where w.rn <= c.page_limit
),
final_cursor as (
  select p.updated_at_server, p.entity, p.entity_id
  from page p
  order by p.updated_at_server desc, p.entity desc, p.entity_id desc
  limit 1
),
meta as (
  select
    c.page_limit,
    c.cursor_text,
    exists (
      select 1
      from windowed w
      where w.rn > c.page_limit
    ) as has_more,
    (
      select
        to_char(fc.updated_at_server at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        || '|' || fc.entity || '|' || fc.entity_id
      from final_cursor fc
    ) as computed_next_cursor
  from cursor_parts c
)
select
  coalesce(
    (
      select jsonb_agg(
        case
          when p.is_deleted then
            jsonb_build_object(
              'entity', p.entity,
              'type', 'delete',
              'entityId', p.entity_id,
              'version', p.version
            )
          else
            jsonb_build_object(
              'entity', p.entity,
              'type', 'upsert',
              'doc', p.doc
            )
        end
        order by p.updated_at_server, p.entity, p.entity_id
      )
      from page p
    ),
    '[]'::jsonb
  ) as changes,
  coalesce(m.computed_next_cursor, coalesce(m.cursor_text, '1970-01-01T00:00:00.000000Z')) as next_cursor,
  m.has_more
from meta m;
$$;

grant execute on function public.sync_pull_page(uuid, text, integer) to authenticated;

commit;
