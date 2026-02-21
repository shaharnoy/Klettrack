-- Performance advisor remediations:
-- 1) Replace direct auth.uid() in RLS policies with (select auth.uid()) to avoid per-row re-evaluation.
-- 2) Add missing FK covering indexes for plan_days.day_type_id and plans.kind_id.

begin;

create index if not exists plan_days_day_type_id_idx on public.plan_days (day_type_id);
create index if not exists plans_kind_id_idx on public.plans (kind_id);

do $$
declare
  policy_row record;
  rewritten_using text;
  rewritten_with_check text;
begin
  for policy_row in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        (qual is not null and qual like '%auth.uid()%')
        or (with_check is not null and with_check like '%auth.uid()%')
      )
  loop
    rewritten_using := case
      when policy_row.qual is null then null
      else replace(policy_row.qual, 'auth.uid()', '(select auth.uid())')
    end;

    rewritten_with_check := case
      when policy_row.with_check is null then null
      else replace(policy_row.with_check, 'auth.uid()', '(select auth.uid())')
    end;

    if rewritten_using is not null and rewritten_with_check is not null then
      execute format(
        'alter policy %I on %I.%I using (%s) with check (%s)',
        policy_row.policyname,
        policy_row.schemaname,
        policy_row.tablename,
        rewritten_using,
        rewritten_with_check
      );
    elsif rewritten_using is not null then
      execute format(
        'alter policy %I on %I.%I using (%s)',
        policy_row.policyname,
        policy_row.schemaname,
        policy_row.tablename,
        rewritten_using
      );
    elsif rewritten_with_check is not null then
      execute format(
        'alter policy %I on %I.%I with check (%s)',
        policy_row.policyname,
        policy_row.schemaname,
        policy_row.tablename,
        rewritten_with_check
      );
    end if;
  end loop;
end
$$;

commit;
