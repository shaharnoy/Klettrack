-- Security hardening: pin function search_path for sync pull RPC.
alter function public.sync_pull_page(uuid, text, integer) set search_path = public, pg_temp;
