-- 0004 · Rename uwu_boards to uwuboard_boards
--
-- uwuBoard's own tables take the uwuboard_ prefix. The sign-in tables, uwu_users and
-- uwu_sessions, keep their names: they're shared by the UwU Apps.
--
-- A straight rename. The API from this migration on reads uwuboard_boards, the API before it
-- reads uwu_boards, so run this as the deploy that uses the new name goes live: in between,
-- signed-in boards can't be loaded or saved.
--
-- The rows, the RLS setting, the foreign key to uwu_users and the updated_at trigger all go
-- with the table. Its index, key and trigger are renamed to match, where they exist.
--
-- Safe to run more than once.

alter table if exists public.uwu_boards rename to uwuboard_boards;

do $$
begin
  if to_regclass('public.uwu_boards_pkey') is not null then
    alter index public.uwu_boards_pkey rename to uwuboard_boards_pkey;
  end if;

  if to_regclass('public.uwu_boards_user_id_idx') is not null then
    alter index public.uwu_boards_user_id_idx rename to uwuboard_boards_user_id_idx;
  end if;

  if exists (
    select 1 from pg_trigger
    where tgname = 'uwu_boards_set_updated_at'
      and tgrelid = to_regclass('public.uwuboard_boards')
  ) then
    alter trigger uwu_boards_set_updated_at on public.uwuboard_boards
      rename to uwuboard_boards_set_updated_at;
  end if;
end
$$;
