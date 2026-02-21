-- Security hardening for trigger function used by sync tables.
alter function public.apply_sync_metadata() set search_path = public, pg_temp;
