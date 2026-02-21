-- Sync v1 schema for plans + catalog.
-- Owner-scoped tables with shared sync metadata, soft deletes, and RLS.

begin;

-- Shared trigger function for sync metadata.
create or replace function public.apply_sync_metadata()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.version := coalesce(new.version, 1);
    new.updated_at_server := coalesce(new.updated_at_server, now());
    return new;
  end if;

  -- Prevent ownership transfer.
  if new.owner_id <> old.owner_id then
    raise exception 'owner_id is immutable';
  end if;

  new.version := old.version + 1;
  new.updated_at_server := now();
  return new;
end;
$$;

create table if not exists public.plan_kinds (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  name text not null,
  total_weeks integer,
  is_repeating boolean not null default false,
  display_order integer not null default 0,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint plan_kinds_total_weeks_valid check (total_weeks is null or total_weeks > 0)
);

create table if not exists public.day_types (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  name text not null,
  display_order integer not null default 0,
  color_key text not null default 'gray',
  is_default boolean not null default false,
  is_hidden boolean not null default false,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.plans (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  kind_id uuid references public.plan_kinds(id) on delete set null,
  start_date timestamptz not null,
  recurring_chosen_exercises_by_weekday jsonb not null default '{}'::jsonb,
  recurring_exercise_order_by_weekday jsonb not null default '{}'::jsonb,
  recurring_day_type_id_by_weekday jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.plan_days (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.plans(id) on delete cascade,
  day_date timestamptz not null,
  day_type_id uuid references public.day_types(id) on delete set null,
  chosen_exercise_ids jsonb not null default '[]'::jsonb,
  exercise_order_by_id jsonb not null default '{}'::jsonb,
  daily_notes text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.activities (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.training_types (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  activity_id uuid references public.activities(id) on delete set null,
  name text not null,
  area text,
  type_description text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.exercises (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  training_type_id uuid references public.training_types(id) on delete set null,
  name text not null,
  area text,
  display_order integer not null default 0,
  exercise_description text,
  reps_text text,
  duration_text text,
  sets_text text,
  rest_text text,
  notes text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.boulder_combinations (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  training_type_id uuid references public.training_types(id) on delete set null,
  name text not null,
  combo_description text,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.boulder_combination_exercises (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  boulder_combination_id uuid not null references public.boulder_combinations(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  display_order integer not null default 0,
  version integer not null default 1,
  updated_at_server timestamptz not null default now(),
  updated_at_client timestamptz,
  last_op_id uuid,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  constraint boulder_combination_exercises_unique unique (owner_id, boulder_combination_id, exercise_id)
);

-- Per-table indexes for owner + cursor pulls.
create index if not exists plan_kinds_owner_updated_idx on public.plan_kinds (owner_id, updated_at_server);
create index if not exists day_types_owner_updated_idx on public.day_types (owner_id, updated_at_server);
create index if not exists plans_owner_updated_idx on public.plans (owner_id, updated_at_server);
create index if not exists plan_days_owner_updated_idx on public.plan_days (owner_id, updated_at_server);
create index if not exists activities_owner_updated_idx on public.activities (owner_id, updated_at_server);
create index if not exists training_types_owner_updated_idx on public.training_types (owner_id, updated_at_server);
create index if not exists exercises_owner_updated_idx on public.exercises (owner_id, updated_at_server);
create index if not exists boulder_combinations_owner_updated_idx on public.boulder_combinations (owner_id, updated_at_server);
create index if not exists boulder_combination_exercises_owner_updated_idx on public.boulder_combination_exercises (owner_id, updated_at_server);

create index if not exists plan_days_plan_id_idx on public.plan_days (plan_id);
create index if not exists training_types_activity_id_idx on public.training_types (activity_id);
create index if not exists exercises_training_type_id_idx on public.exercises (training_type_id);
create index if not exists boulder_combinations_training_type_id_idx on public.boulder_combinations (training_type_id);
create index if not exists boulder_combination_exercises_combo_id_idx on public.boulder_combination_exercises (boulder_combination_id);
create index if not exists boulder_combination_exercises_exercise_id_idx on public.boulder_combination_exercises (exercise_id);

-- Sync metadata triggers.
drop trigger if exists plan_kinds_sync_metadata on public.plan_kinds;
create trigger plan_kinds_sync_metadata before insert or update on public.plan_kinds
for each row execute function public.apply_sync_metadata();

drop trigger if exists day_types_sync_metadata on public.day_types;
create trigger day_types_sync_metadata before insert or update on public.day_types
for each row execute function public.apply_sync_metadata();

drop trigger if exists plans_sync_metadata on public.plans;
create trigger plans_sync_metadata before insert or update on public.plans
for each row execute function public.apply_sync_metadata();

drop trigger if exists plan_days_sync_metadata on public.plan_days;
create trigger plan_days_sync_metadata before insert or update on public.plan_days
for each row execute function public.apply_sync_metadata();

drop trigger if exists activities_sync_metadata on public.activities;
create trigger activities_sync_metadata before insert or update on public.activities
for each row execute function public.apply_sync_metadata();

drop trigger if exists training_types_sync_metadata on public.training_types;
create trigger training_types_sync_metadata before insert or update on public.training_types
for each row execute function public.apply_sync_metadata();

drop trigger if exists exercises_sync_metadata on public.exercises;
create trigger exercises_sync_metadata before insert or update on public.exercises
for each row execute function public.apply_sync_metadata();

drop trigger if exists boulder_combinations_sync_metadata on public.boulder_combinations;
create trigger boulder_combinations_sync_metadata before insert or update on public.boulder_combinations
for each row execute function public.apply_sync_metadata();

drop trigger if exists boulder_combination_exercises_sync_metadata on public.boulder_combination_exercises;
create trigger boulder_combination_exercises_sync_metadata before insert or update on public.boulder_combination_exercises
for each row execute function public.apply_sync_metadata();

-- Enable RLS and owner-only policies.
alter table public.plan_kinds enable row level security;
alter table public.day_types enable row level security;
alter table public.plans enable row level security;
alter table public.plan_days enable row level security;
alter table public.activities enable row level security;
alter table public.training_types enable row level security;
alter table public.exercises enable row level security;
alter table public.boulder_combinations enable row level security;
alter table public.boulder_combination_exercises enable row level security;

-- plan_kinds policies
drop policy if exists plan_kinds_owner_select on public.plan_kinds;
create policy plan_kinds_owner_select on public.plan_kinds
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists plan_kinds_owner_insert on public.plan_kinds;
create policy plan_kinds_owner_insert on public.plan_kinds
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists plan_kinds_owner_update on public.plan_kinds;
create policy plan_kinds_owner_update on public.plan_kinds
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists plan_kinds_owner_delete on public.plan_kinds;
create policy plan_kinds_owner_delete on public.plan_kinds
for delete to authenticated
using (owner_id = auth.uid());

-- day_types policies
drop policy if exists day_types_owner_select on public.day_types;
create policy day_types_owner_select on public.day_types
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists day_types_owner_insert on public.day_types;
create policy day_types_owner_insert on public.day_types
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists day_types_owner_update on public.day_types;
create policy day_types_owner_update on public.day_types
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists day_types_owner_delete on public.day_types;
create policy day_types_owner_delete on public.day_types
for delete to authenticated
using (owner_id = auth.uid());

-- plans policies
drop policy if exists plans_owner_select on public.plans;
create policy plans_owner_select on public.plans
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists plans_owner_insert on public.plans;
create policy plans_owner_insert on public.plans
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists plans_owner_update on public.plans;
create policy plans_owner_update on public.plans
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists plans_owner_delete on public.plans;
create policy plans_owner_delete on public.plans
for delete to authenticated
using (owner_id = auth.uid());

-- plan_days policies
drop policy if exists plan_days_owner_select on public.plan_days;
create policy plan_days_owner_select on public.plan_days
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists plan_days_owner_insert on public.plan_days;
create policy plan_days_owner_insert on public.plan_days
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists plan_days_owner_update on public.plan_days;
create policy plan_days_owner_update on public.plan_days
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists plan_days_owner_delete on public.plan_days;
create policy plan_days_owner_delete on public.plan_days
for delete to authenticated
using (owner_id = auth.uid());

-- activities policies
drop policy if exists activities_owner_select on public.activities;
create policy activities_owner_select on public.activities
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists activities_owner_insert on public.activities;
create policy activities_owner_insert on public.activities
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists activities_owner_update on public.activities;
create policy activities_owner_update on public.activities
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists activities_owner_delete on public.activities;
create policy activities_owner_delete on public.activities
for delete to authenticated
using (owner_id = auth.uid());

-- training_types policies
drop policy if exists training_types_owner_select on public.training_types;
create policy training_types_owner_select on public.training_types
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists training_types_owner_insert on public.training_types;
create policy training_types_owner_insert on public.training_types
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists training_types_owner_update on public.training_types;
create policy training_types_owner_update on public.training_types
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists training_types_owner_delete on public.training_types;
create policy training_types_owner_delete on public.training_types
for delete to authenticated
using (owner_id = auth.uid());

-- exercises policies
drop policy if exists exercises_owner_select on public.exercises;
create policy exercises_owner_select on public.exercises
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists exercises_owner_insert on public.exercises;
create policy exercises_owner_insert on public.exercises
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists exercises_owner_update on public.exercises;
create policy exercises_owner_update on public.exercises
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists exercises_owner_delete on public.exercises;
create policy exercises_owner_delete on public.exercises
for delete to authenticated
using (owner_id = auth.uid());

-- boulder_combinations policies
drop policy if exists boulder_combinations_owner_select on public.boulder_combinations;
create policy boulder_combinations_owner_select on public.boulder_combinations
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists boulder_combinations_owner_insert on public.boulder_combinations;
create policy boulder_combinations_owner_insert on public.boulder_combinations
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists boulder_combinations_owner_update on public.boulder_combinations;
create policy boulder_combinations_owner_update on public.boulder_combinations
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists boulder_combinations_owner_delete on public.boulder_combinations;
create policy boulder_combinations_owner_delete on public.boulder_combinations
for delete to authenticated
using (owner_id = auth.uid());

-- boulder_combination_exercises policies
drop policy if exists boulder_combination_exercises_owner_select on public.boulder_combination_exercises;
create policy boulder_combination_exercises_owner_select on public.boulder_combination_exercises
for select to authenticated
using (owner_id = auth.uid());

drop policy if exists boulder_combination_exercises_owner_insert on public.boulder_combination_exercises;
create policy boulder_combination_exercises_owner_insert on public.boulder_combination_exercises
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists boulder_combination_exercises_owner_update on public.boulder_combination_exercises;
create policy boulder_combination_exercises_owner_update on public.boulder_combination_exercises
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists boulder_combination_exercises_owner_delete on public.boulder_combination_exercises;
create policy boulder_combination_exercises_owner_delete on public.boulder_combination_exercises
for delete to authenticated
using (owner_id = auth.uid());

commit;
