# Database migrations

SQL to run in the Supabase SQL editor, in number order. Each file says what it does and when to
run it, and each is safe to run more than once.

**A migration is never edited once it's written.** A change to the database is a new file with
the next number, so these files always say exactly what was run.

| File | What it does | When |
| --- | --- | --- |
| `0001_baseline_schema.sql` | The users, sessions and boards tables and the two image buckets, created only where missing. Changes nothing on an existing database. | Any time. |
| `0002_lock_tables_with_rls.sql` | Turns on Row Level Security, with no policies, so the public anon key can't read the tables. The API uses the service role key and isn't affected. | Any time. |
| `0003_make_image_buckets_private.sql` | Makes `card-images` and `avatars` private. Images are served through the API, so the app is unaffected; old public image URLs stop working everywhere. | Any time. |
| `0004_rename_boards_to_uwuboard_boards.sql` | Renames `uwu_boards` to `uwuboard_boards`. | As the deploy that reads `uwuboard_boards` goes live. Until both have happened, signed-in boards can't load or save. |

## Running them

1. Open the project in Supabase, then **SQL Editor → New query**.
2. Paste in one file, run it, and check it finished without an error.
3. Go on to the next.

On a brand-new Supabase project, run them all in order before the first deploy.
