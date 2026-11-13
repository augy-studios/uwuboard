import { expect } from "@playwright/test";

export const API = "https://board.uwuapps.org/api";

/**
 * The site's API, answered here: a guest touches none of it; a signed-in session reads and writes
 * boards in `db`. Every request is kept in `db.requests`, with its Authorization header.
 */
export async function mockApi(page, db = {}) {
  db.boards ??= [];
  db.requests = [];
  db.release ??= { version: null, history: [] };
  await page.route(`${API}/**`, async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const path = url.pathname.replace(/^\/api/, "");
    const body = req.postData() ? JSON.parse(req.postData()) : null;
    db.requests.push({ method: req.method(), path, body, auth: req.headers()["authorization"] || null });
    const json = (status, data) => route.fulfill({ status, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(data) });
    if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    switch (path) {
      case "/auth/login":
        if (body?.password !== "correct horse") return json(401, { error: "Invalid username or password" });
        return json(200, { username: body.username, displayName: "Sam", hasAvatar: false, session: { token: "tok-123", userId: "u1" } });
      case "/auth/logout":
        return json(200, { ok: true });
      case "/boards/list":
        return json(200, { boards: db.boards });
      case "/boards/create":
      case "/boards/update": {
        const i = db.boards.findIndex((b) => b.id === body.board.id);
        if (i >= 0) db.boards[i] = body.board; else db.boards.push(body.board);
        return json(200, { ok: true });
      }
      case "/boards/delete":
        db.boards = db.boards.filter((b) => b.id !== body.boardId);
        return json(200, { ok: true });
      case "/app-release":
        return json(200, db.release);
      default:
        return json(404, { error: "Not found" });
    }
  });
  return db;
}

/** The app, up, with the errors it logs collected. `query` like "?android=1". */
export async function openApp(page, query = "") {
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => {
    if (m.type() === "error" && !/favicon|Failed to load resource|peerjs/i.test(m.text())) errors.push(m.text());
  });
  await page.goto(`/${query}`);
  page.appErrors = errors;
  return errors;
}

export const button = (page, name, exact = true) => page.getByRole("button", { name, exact });

/** What the app keeps, as shared_preferences has it in the browser (store.dart's "ls." prefix). */
export const stored = (page, key) =>
  page.evaluate((k) => {
    const v = localStorage.getItem(`flutter.ls.${k}`);
    return v === null ? null : JSON.parse(v);
  }, key);

export const guestBoards = async (page) => JSON.parse((await stored(page, "kanbanflow_guest_boards")) ?? "[]");

/** What the app asked of its Android side. */
export const calls = (page) => page.evaluate(() => Array.from(window.e2eCalls || []).map((c) => JSON.parse(c)));

/** Types into the text field with this label or hint. */
export async function fill(page, locator, text) {
  await locator.click();
  await page.waitForTimeout(200);
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

/** As a guest, past the first tour. */
export async function startAsGuest(page) {
  await button(page, "Guest").click();
  await button(page, "Continue as Guest").click();
  await expect(page.getByText("Select or create a board to get started")).toBeVisible();
  await skipTour(page);
}

/** A tour on screen goes. */
export async function skipTour(page) {
  const skip = button(page, "Skip");
  try {
    await skip.waitFor({ timeout: 3500 });
    await skip.click();
  } catch {
    // None this time.
  }
}

export async function newBoard(page, name, type = "Kanban") {
  await button(page, "Create Board").click().catch(async () => button(page, "New Board").click());
  const nameBox = page.getByRole("textbox").first();
  await fill(page, nameBox, name);
  if (type !== "Kanban") await page.getByRole("radio", { name: new RegExp(`^${type}`) }).click();
  await button(page, "Create").click();
  await expect(page.getByRole("heading", { name })).toBeVisible();
}

export function noErrors(page) {
  expect(page.appErrors.filter((e) => !/WebSocket|peerjs|broker/i.test(e))).toEqual([]);
}

/** A toast or note: said once to a screen reader and once on screen, so the one on screen. */
export const said = (page, text) => page.getByText(text).last();
