-- 0001 · Baseline schema
--
-- The tables and storage buckets uwuBoard's API uses, as they stood before any numbered
-- migration. Everything here is created only where it's missing: on the existing database
-- this changes nothing, and on a new Supabase project it sets everything up.
--
-- Safe to run more than once.

-- Accounts, shared by the UwU Apps.
create table if not exists public.uwu_users (
  id            uuid primary key default gen_random_uuid(),
  username      text not null unique,
  email         text not null unique,
  password_hash text not null,
  display_name  text,
  avatar_url    text,
  created_at    timestamptz not null default now()
);

-- Signed-in sessions: a random token per sign-in, kept 30 days.
do $$
begin
  if to_regclass('public.uwu_sessions') is null then
    create table public.uwu_sessions (
      token      text primary key,
      user_id    uuid not null references public.uwu_users (id) on delete cascade,
      expires_at timestamptz not null,
      created_at timestamptz not null default now()
    );
    create index uwu_sessions_user_id_idx on public.uwu_sessions (user_id);
  end if;
end
$$;

-- Boards. `id` is made by the page; `data` holds the columns, cards and how the board is shown.
-- Not made again once a later migration has renamed it (0004: uwuboard_boards).
do $$
begin
  if to_regclass('public.uwu_boards') is null and to_regclass('public.uwuboard_boards') is null then
    create table public.uwu_boards (
      id         text primary key,
      user_id    uuid not null references public.uwu_users (id) on delete cascade,
      name       text not null,
      data       jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
    create index uwu_boards_user_id_idx on public.uwu_boards (user_id);

    create or replace function public.uwu_set_updated_at() returns trigger
      language plpgsql as $f$
      begin
        new.updated_at := now();
        return new;
      end
      $f$;

    create trigger uwu_boards_set_updated_at
      before update on public.uwu_boards
      for each row execute function public.uwu_set_updated_at();
  end if;
end
$$;

-- Storage: card images under <user id>/<file>, avatars under <user id>/avatar.<ext>.
-- Public, as they were before images were served through the API (0003 makes them private).
insert into storage.buckets (id, name, public)
values
  ('card-images', 'card-images', true),
  ('avatars', 'avatars', true)
on conflict (id) do nothing;
