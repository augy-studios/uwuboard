# uwuBoard

A ClickUp × Trello-style kanban web app

## Features

- **Accounts** — register/login with username + password; 30-day sessions
- **Guest mode** — no account needed; boards persist in `localStorage`; export/import JSON to move between browsers
- **Boards** — unlimited boards per user; rename, delete
- **Columns** — editable number of columns; rename, delete, reorder via drag
- **Cards** — titles, descriptions, due dates, priority flags, colour labels, checklists, drag-and-drop between columns
- **Report a bug** — from the edge tray, with Screenshot a page and a report ID, sent through a Telegram bot (`js/bug-report.js`, `api/bug-report.js`; the top-level README's "Report a bug" says how to set it up)
- **PWA** — installable and offline-capable
- **Liquid glass UI** — `#ccffcc` brand, specular highlights, backdrop blur