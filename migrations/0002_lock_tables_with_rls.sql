-- 0002 · Lock the tables with Row Level Security
--
-- Turns RLS on, with no policies, for every table uwuBoard uses. uwuBoard's API connects with
-- the service role key, which bypasses RLS, so the app works exactly as before. What changes:
-- anyone holding the project's public anon key can no longer read or write users, sessions
-- or boards directly through Supabase.
--
-- Safe to run more than once.

alter table if exists public.uwu_users    enable row level security;
alter table if exists public.uwu_sessions enable row level security;
alter table if exists public.uwu_boards   enable row level security;
