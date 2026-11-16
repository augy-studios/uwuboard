import { expect } from "@playwright/test";

export const API = "https://board.uwuapps.org/api";

/**
 * The site's API, answered here: a guest touches none of it; a signed-in session reads and writes
 * boards in `database`. Every request is kept in `database.requests`, with its Authorization header.
 */
export async function mockApi(page, database = {}) {
  if (database.boards === null || database.boards === undefined) {
    database.boards = [];
  }
  database.requests = [];
  if (database.release === null || database.release === undefined) {
    database.release = { version: null, history: [] };
  }
  await page.route(`${API}/**`, async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api/, "");
    let body;
    if (request.postData()) {
      body = JSON.parse(request.postData());
    } else {
      body = null;
    }
    const method = request.method();
    let authorization = request.headers()["authorization"];
    if (!authorization) {
      authorization = null;
    }
    database.requests.push({ method, path, body, auth: authorization });
    // Answers the request with this status and this data as JSON.
    const json = (status, data) => {
      return route.fulfill({ status, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(data) });
    };
    if (request.method() === "OPTIONS") {
      return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    }
    switch (path) {
      case "/auth/login": {
        let password;
        if (body !== null && body !== undefined) {
          password = body.password;
        } else {
          password = undefined;
        }
        if (password !== "correct horse") {
          return json(401, { error: "Invalid username or password" });
        }
        return json(200, { username: body.username, displayName: "Sam", hasAvatar: false, session: { token: "tok-123", userId: "u1" } });
      }
      case "/auth/logout":
        return json(200, { ok: true });
      case "/boards/list":
        return json(200, { boards: database.boards });
      case "/boards/create":
      case "/boards/update": {
        const index = database.boards.findIndex((board) => {
          return board.id === body.board.id;
        });
        if (index >= 0) {
          database.boards[index] = body.board;
        } else {
          database.boards.push(body.board);
        }
        return json(200, { ok: true });
      }
      case "/boards/delete":
        database.boards = database.boards.filter((board) => {
          return board.id !== body.boardId;
        });
        return json(200, { ok: true });
      case "/app-release":
        return json(200, database.release);
      // Report a bug (main-site/api/bug-report.js): kept in database.bugReports; database.bugStatus sets the answer.
      case "/bug-report":
        if (database.bugReports === null || database.bugReports === undefined) {
          database.bugReports = [];
        }
        database.bugReports.push(body);
        if (database.bugStatus && database.bugStatus !== 200) {
          return json(database.bugStatus, { error: "Bug reports can't be sent from the app yet." });
        }
        return json(200, { id: "20261114-7K3Q" });
      default:
        return json(404, { error: "Not found" });
    }
  });
  return database;
}

/** The app, up, with the errors it logs collected. `query` like "?android=1". */
export async function openApp(page, query = "") {
  const errors = [];
  page.on("pageerror", (error) => {
    errors.push(String(error));
  });
  page.on("console", (message) => {
    if (message.type() === "error" && !/favicon|Failed to load resource|peerjs/i.test(message.text())) {
      errors.push(message.text());
    }
  });
  await page.goto(`/${query}`);
  page.appErrors = errors;
  return errors;
}

/** The button with this name (matched exactly unless `exact` is false). */
export const button = (page, name, exact = true) => {
  return page.getByRole("button", { name, exact });
};

/** What the app keeps, as shared_preferences has it in the browser (store.dart's "ls." prefix). */
export const stored = (page, key) => {
  return page.evaluate((storageKey) => {
    const value = localStorage.getItem(`flutter.ls.${storageKey}`);
    if (value === null) {
      return null;
    } else {
      return JSON.parse(value);
    }
  }, key);
};

/** The guest's boards as the app saved them (an empty list when there are none yet). */
export const guestBoards = async (page) => {
  let boardsJson = await stored(page, "kanbanflow_guest_boards");
  if (boardsJson === null || boardsJson === undefined) {
    boardsJson = "[]";
  }
  return JSON.parse(boardsJson);
};

/** What the app asked of its Android side. */
export const calls = (page) => {
  return page.evaluate(() => {
    let recordedCalls = window.e2eCalls;
    if (!recordedCalls) {
      recordedCalls = [];
    }
    return Array.from(recordedCalls).map((call) => {
      return JSON.parse(call);
    });
  });
};

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

/**
 * Makes a new board with this name and type ("Kanban" unless another is given) and waits for it
 * to open. The button is "Create Board" with no boards yet and "New Board" once there are some.
 */
export async function newBoard(page, name, type = "Kanban") {
  await button(page, "Create Board").click().catch(async () => {
    return button(page, "New Board").click();
  });
  const nameBox = page.getByRole("textbox").first();
  await fill(page, nameBox, name);
  if (type !== "Kanban") {
    await page.getByRole("radio", { name: new RegExp(`^${type}`) }).click();
  }
  await button(page, "Create").click();
  await expect(page.getByRole("heading", { name })).toBeVisible();
}

/** Expects that the app logged no errors, apart from the peer-to-peer sync's connection noise. */
export function noErrors(page) {
  expect(page.appErrors.filter((error) => {
    return !/WebSocket|peerjs|broker/i.test(error);
  })).toEqual([]);
}

/** A toast or note: said once to a screen reader and once on screen, so the one on screen. */
export const said = (page, text) => {
  return page.getByText(text).last();
};
