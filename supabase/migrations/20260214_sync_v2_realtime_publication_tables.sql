begin;

alter publication supabase_realtime add table public.sessions;
alter publication supabase_realtime add table public.session_items;
alter publication supabase_realtime add table public.timer_templates;
alter publication supabase_realtime add table public.timer_intervals;
alter publication supabase_realtime add table public.timer_sessions;
alter publication supabase_realtime add table public.timer_laps;
alter publication supabase_realtime add table public.climb_entries;
alter publication supabase_realtime add table public.climb_styles;
alter publication supabase_realtime add table public.climb_gyms;

commit;
