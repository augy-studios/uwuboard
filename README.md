# uwuBoard

The Kanban way: turn your to-do list into a clear board where you drag tasks from To Do to Done.

uwuBoard is an installable web app (PWA) by Augy Studios. Use it as a guest with everything kept in
your browser, or sign up and your boards follow you to any device.

| Phone | Desktop |
| --- | --- |
| ![uwuBoard on a phone](main-site/images/screenshot_1.png) | ![uwuBoard on a desktop](main-site/images/screenshot_2.png) |

## Features

- **Boards:** as many as you like; rename and delete them.
- **Columns:** add, rename, delete and drag to reorder.
- **Cards:** title, description, due date, priority, colour labels, checklists and images; drag
  them between columns.
- **Guest mode:** no account needed. Boards live in `localStorage`, and you can export them as JSON
  and import them in another browser.
- **Accounts:** username, email and password, with 30-day sessions. Edit your display name and
  avatar, or delete your account.
- **Themes:** seven brand colour swatches and a light, dark or time-based mode.
- **PWA:** installable and works offline. When a new version is ready, a bar at the top offers to
  reload.

## Repository layout

```
main-site/          The web app, deployed to Vercel
  index.html        Single-page app shell
  script.js         Board, card and account logic
  style.css         Styles
  js/               Theme system, icons, UI helpers, update bar
  sw.js             Service worker (offline cache)
  api/              Vercel serverless functions
    auth/           register, login, logout, update-profile, update-avatar, delete-account
    boards/         list, get, create, update, delete
    images/         upload, delete (card images)
    lib/            Supabase client and session check
docs/               Specs for features and for the planned Android and desktop apps
```

## Tech stack

- Plain HTML, CSS and JavaScript on the front end, with no framework and no build step.
- [Vercel](https://vercel.com) serverless functions (Node.js) for the API, in the `sin1` region.
- [Supabase](https://supabase.com) for Postgres and file storage.
- `bcryptjs` for password hashing.

## Running it locally

You need Node.js, the [Vercel CLI](https://vercel.com/docs/cli) and a Supabase project.

```sh
cd main-site
npm install
vercel dev
```

Guest mode works without a backend. Accounts, synced boards and images need the Supabase setup below.

### Environment variables

Set these in the Vercel project, or in `main-site/.env.local` for `vercel dev`:

| Variable | What it is |
| --- | --- |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_KEY` | The service role key. It is only used server side, so never expose it to the browser. |

### Supabase

The API expects these tables:

| Table | Columns |
| --- | --- |
| `uwu_users` | `id`, `username` (unique), `email` (unique), `password_hash`, `display_name`, `avatar_url` |
| `uwu_sessions` | `token`, `user_id` → `uwu_users.id`, `expires_at` |
| `uwu_boards` | `id` (made by the client), `user_id` → `uwu_users.id`, `name`, `data` (JSON holding the columns), `created_at`, `updated_at` |

It also expects two public storage buckets: `card-images` and `avatars`.

## Deploying

Deploy `main-site/` as a Vercel project. `vercel.json` maps the clean `/api/...` routes to their
functions.

Every change to a file the service worker caches (HTML, JS, CSS, the manifest, icons) must bump
`VERSION` in [main-site/sw.js](main-site/sw.js). Otherwise anyone who already has the site cached
won't get the update.

## Docs

[docs/](docs/) holds specs that don't depend on any one framework. Some cover features in this app
(the update bar, page tours, the edge tray, hiding image locations, time-based theme mode). Others
cover the planned Flutter apps for Android and desktop, and peer-to-peer pairing over STUN.

## Contributing

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before taking part.

## License

[MIT](LICENSE) © 2026 Augy Studios
