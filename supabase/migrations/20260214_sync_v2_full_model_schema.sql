-- Sync v2 schema expansion for sessions, timers, and climbing entities.
-- Extends v1 owner-scoped sync model with metadata trigger and RLS.

begin;

create table if not exists public.sessions (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  session_date timestamptz not null,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.session_items (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  source_tag text,
  exercise_name text not null,
  sort_order integer not null default 0,
  plan_source_id uuid,
  plan_name text,
  reps double precision,
  sets double precision,
  weight_kg double precision,
  grade text,
  notes text,
  duration double precision,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.timer_templates (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  template_description text,
  total_time_seconds integer,
  is_repeating boolean not null default false,
  repeat_count integer,
  rest_time_between_intervals integer,
  created_date timestamptz not null,
  last_used_date timestamptz,
  use_count integer not null default 0,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint timer_templates_total_time_non_negative check (total_time_seconds is null or total_time_seconds >= 0),
  constraint timer_templates_repeat_count_valid check (repeat_count is null or repeat_count > 0),
  constraint timer_templates_rest_between_non_negative check (rest_time_between_intervals is null or rest_time_between_intervals >= 0),
  constraint timer_templates_use_count_non_negative check (use_count >= 0)
);

create table if not exists public.timer_intervals (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  timer_template_id uuid references public.timer_templates(id) on delete set null,
  name text not null,
  work_time_seconds integer not null default 0,
  rest_time_seconds integer not null default 0,
  repetitions integer not null default 1,
  display_order integer not null default 0,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint timer_intervals_work_non_negative check (work_time_seconds >= 0),
  constraint timer_intervals_rest_non_negative check (rest_time_seconds >= 0),
  constraint timer_intervals_repetitions_positive check (repetitions > 0)
);

create table if not exists public.timer_sessions (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  start_date timestamptz not null,
  end_date timestamptz,
  timer_template_id uuid references public.timer_templates(id) on delete set null,
  template_name text,
  plan_day_id uuid references public.plan_days(id) on delete set null,
  total_elapsed_seconds integer not null default 0,
  completed_intervals integer not null default 0,
  was_completed boolean not null default false,
  daily_notes text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint timer_sessions_elapsed_non_negative check (total_elapsed_seconds >= 0),
  constraint timer_sessions_completed_non_negative check (completed_intervals >= 0)
);

create table if not exists public.timer_laps (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  timer_session_id uuid references public.timer_sessions(id) on delete set null,
  lap_number integer not null,
  timestamp timestamptz not null,
  elapsed_seconds integer not null default 0,
  notes text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint timer_laps_lap_number_positive check (lap_number > 0),
  constraint timer_laps_elapsed_non_negative check (elapsed_seconds >= 0)
);

create table if not exists public.climb_entries (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  climb_type text not null,
  rope_climb_type text,
  grade text not null,
  feels_like_grade text,
  angle_degrees integer,
  style text not null,
  attempts text,
  is_work_in_progress boolean not null default false,
  is_previously_climbed boolean,
  hold_color text,
  gym text not null,
  notes text,
  date_logged timestamptz not null,
  tb2_climb_uuid text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint climb_entries_angle_valid check (angle_degrees is null or (angle_degrees >= -90 and angle_degrees <= 90))
);

create table if not exists public.climb_styles (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  is_hidden boolean not null default false,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.climb_gyms (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists sessions_owner_updated_idx on public.sessions (owner_id, updated_at_server);
create index if not exists session_items_owner_updated_idx on public.session_items (owner_id, updated_at_server);
create index if not exists timer_templates_owner_updated_idx on public.timer_templates (owner_id, updated_at_server);
create index if not exists timer_intervals_owner_updated_idx on public.timer_intervals (owner_id, updated_at_server);
create index if not exists timer_sessions_owner_updated_idx on public.timer_sessions (owner_id, updated_at_server);
create index if not exists timer_laps_owner_updated_idx on public.timer_laps (owner_id, updated_at_server);
create index if not exists climb_entries_owner_updated_idx on public.climb_entries (owner_id, updated_at_server);
create index if not exists climb_styles_owner_updated_idx on public.climb_styles (owner_id, updated_at_server);
create index if not exists climb_gyms_owner_updated_idx on public.climb_gyms (owner_id, updated_at_server);

create index if not exists session_items_session_id_idx on public.session_items (session_id);
create index if not exists timer_intervals_template_id_idx on public.timer_intervals (timer_template_id);
create index if not exists timer_sessions_template_id_idx on public.timer_sessions (timer_template_id);
create index if not exists timer_sessions_plan_day_id_idx on public.timer_sessions (plan_day_id);
create index if not exists timer_laps_session_id_idx on public.timer_laps (timer_session_id);

drop trigger if exists sessions_sync_metadata on public.sessions;
create trigger sessions_sync_metadata before insert or update on public.sessions
for each row execute function public.apply_sync_metadata();

drop trigger if exists session_items_sync_metadata on public.session_items;
create trigger session_items_sync_metadata before insert or update on public.session_items
for each row execute function public.apply_sync_metadata();

drop trigger if exists timer_templates_sync_metadata on public.timer_templates;
create trigger timer_templates_sync_metadata before insert or update on public.timer_templates
for each row execute function public.apply_sync_metadata();

drop trigger if exists timer_intervals_sync_metadata on public.timer_intervals;
create trigger timer_intervals_sync_metadata before insert or update on public.timer_intervals
for each row execute function public.apply_sync_metadata();

drop trigger if exists timer_sessions_sync_metadata on public.timer_sessions;
create trigger timer_sessions_sync_metadata before insert or update on public.timer_sessions
for each row execute function public.apply_sync_metadata();

drop trigger if exists timer_laps_sync_metadata on public.timer_laps;
create trigger timer_laps_sync_metadata before insert or update on public.timer_laps
for each row execute function public.apply_sync_metadata();

drop trigger if exists climb_entries_sync_metadata on public.climb_entries;
create trigger climb_entries_sync_metadata before insert or update on public.climb_entries
for each row execute function public.apply_sync_metadata();

drop trigger if exists climb_styles_sync_metadata on public.climb_styles;
create trigger climb_styles_sync_metadata before insert or update on public.climb_styles
for each row execute function public.apply_sync_metadata();

drop trigger if exists climb_gyms_sync_metadata on public.climb_gyms;
create trigger climb_gyms_sync_metadata before insert or update on public.climb_gyms
for each row execute function public.apply_sync_metadata();


alter table public.sessions enable row level security;
alter table public.session_items enable row level security;
alter table public.timer_templates enable row level security;
alter table public.timer_intervals enable row level security;
alter table public.timer_sessions enable row level security;
alter table public.timer_laps enable row level security;
alter table public.climb_entries enable row level security;
alter table public.climb_styles enable row level security;
alter table public.climb_gyms enable row level security;

drop policy if exists sessions_owner_select on public.sessions;
create policy sessions_owner_select on public.sessions
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists sessions_owner_insert on public.sessions;
create policy sessions_owner_insert on public.sessions
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists sessions_owner_update on public.sessions;
create policy sessions_owner_update on public.sessions
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists sessions_owner_delete on public.sessions;
create policy sessions_owner_delete on public.sessions
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists session_items_owner_select on public.session_items;
create policy session_items_owner_select on public.session_items
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists session_items_owner_insert on public.session_items;
create policy session_items_owner_insert on public.session_items
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists session_items_owner_update on public.session_items;
create policy session_items_owner_update on public.session_items
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists session_items_owner_delete on public.session_items;
create policy session_items_owner_delete on public.session_items
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists timer_templates_owner_select on public.timer_templates;
create policy timer_templates_owner_select on public.timer_templates
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists timer_templates_owner_insert on public.timer_templates;
create policy timer_templates_owner_insert on public.timer_templates
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists timer_templates_owner_update on public.timer_templates;
create policy timer_templates_owner_update on public.timer_templates
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists timer_templates_owner_delete on public.timer_templates;
create policy timer_templates_owner_delete on public.timer_templates
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists timer_intervals_owner_select on public.timer_intervals;
create policy timer_intervals_owner_select on public.timer_intervals
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists timer_intervals_owner_insert on public.timer_intervals;
create policy timer_intervals_owner_insert on public.timer_intervals
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists timer_intervals_owner_update on public.timer_intervals;
create policy timer_intervals_owner_update on public.timer_intervals
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists timer_intervals_owner_delete on public.timer_intervals;
create policy timer_intervals_owner_delete on public.timer_intervals
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists timer_sessions_owner_select on public.timer_sessions;
create policy timer_sessions_owner_select on public.timer_sessions
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists timer_sessions_owner_insert on public.timer_sessions;
create policy timer_sessions_owner_insert on public.timer_sessions
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists timer_sessions_owner_update on public.timer_sessions;
create policy timer_sessions_owner_update on public.timer_sessions
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists timer_sessions_owner_delete on public.timer_sessions;
create policy timer_sessions_owner_delete on public.timer_sessions
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists timer_laps_owner_select on public.timer_laps;
create policy timer_laps_owner_select on public.timer_laps
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists timer_laps_owner_insert on public.timer_laps;
create policy timer_laps_owner_insert on public.timer_laps
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists timer_laps_owner_update on public.timer_laps;
create policy timer_laps_owner_update on public.timer_laps
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists timer_laps_owner_delete on public.timer_laps;
create policy timer_laps_owner_delete on public.timer_laps
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists climb_entries_owner_select on public.climb_entries;
create policy climb_entries_owner_select on public.climb_entries
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists climb_entries_owner_insert on public.climb_entries;
create policy climb_entries_owner_insert on public.climb_entries
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists climb_entries_owner_update on public.climb_entries;
create policy climb_entries_owner_update on public.climb_entries
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists climb_entries_owner_delete on public.climb_entries;
create policy climb_entries_owner_delete on public.climb_entries
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists climb_styles_owner_select on public.climb_styles;
create policy climb_styles_owner_select on public.climb_styles
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists climb_styles_owner_insert on public.climb_styles;
create policy climb_styles_owner_insert on public.climb_styles
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists climb_styles_owner_update on public.climb_styles;
create policy climb_styles_owner_update on public.climb_styles
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists climb_styles_owner_delete on public.climb_styles;
create policy climb_styles_owner_delete on public.climb_styles
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists climb_gyms_owner_select on public.climb_gyms;
create policy climb_gyms_owner_select on public.climb_gyms
for select to authenticated
using (owner_id = auth.uid());
drop policy if exists climb_gyms_owner_insert on public.climb_gyms;
create policy climb_gyms_owner_insert on public.climb_gyms
for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists climb_gyms_owner_update on public.climb_gyms;
create policy climb_gyms_owner_update on public.climb_gyms
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
drop policy if exists climb_gyms_owner_delete on public.climb_gyms;
create policy climb_gyms_owner_delete on public.climb_gyms
for delete to authenticated
using (owner_id = auth.uid());

commit;
