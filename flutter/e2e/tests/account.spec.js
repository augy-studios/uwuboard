import { expect, test } from "@playwright/test";
import { button, fill, mockApi, noErrors, openApp, skipTour, stored , said } from "./helpers.js";

test("signing in reads the account's boards with its token, saves to the API, and signs out", async ({ page }) => {
  const db = await mockApi(page, {
    boards: [{ id: "srv1", name: "Work", view: "kanban", updatedAt: 5, columns: [{ id: "c1", name: "To Do", updatedAt: 5, cards: [] }] }],
  });
  await openApp(page);
  const boxes = page.getByRole("textbox");
  await fill(page, boxes.nth(0), "sam");
  await fill(page, boxes.nth(1), "wrong");
  await button(page, "Sign In").last().click();
  await expect(said(page, "Invalid username or password")).toBeVisible();

  await fill(page, boxes.nth(1), "correct horse");
  await button(page, "Sign In").last().click();
  await skipTour(page);
  await expect(page.getByRole("heading", { name: "Work" })).toBeVisible();
  const list = db.requests.find((r) => r.path === "/boards/list");
  expect(list.auth).toBe("Bearer tok-123");
  expect(JSON.parse(await stored(page, "uwuboard_session"))).toMatchObject({ username: "sam", displayName: "Sam", session: { token: "tok-123" } });

  await page.getByRole("button", { name: "Boards" }).click();
  await button(page, "New Board").click();
  await page.waitForTimeout(300);
  await page.keyboard.type("Personal");
  await button(page, "Create").click();
  await expect(page.getByRole("heading", { name: "Personal" })).toBeVisible();
  const create = db.requests.find((r) => r.path === "/boards/create");
  expect(create.body.board).toMatchObject({ name: "Personal", view: "kanban" });
  expect(create.auth).toBe("Bearer tok-123");

  await page.getByRole("button", { name: "Boards" }).click();
  await button(page, "Sign out").click();
  await expect(button(page, "Guest")).toBeVisible();
  expect(await stored(page, "uwuboard_session")).toBeNull();
  expect(db.requests.some((r) => r.path === "/auth/logout")).toBe(true);
  noErrors(page);
});

test("a saved session opens straight into the boards", async ({ page }) => {
  await mockApi(page, { boards: [{ id: "srv2", name: "Saved", view: "kanban", updatedAt: 1, columns: [] }] });
  await page.addInitScript(() => {
    localStorage.setItem("flutter.ls.uwuboard_session", JSON.stringify(JSON.stringify({ session: { token: "tok-123", userId: "u1" }, username: "sam", displayName: "Sam", hasAvatar: false })));
    localStorage.setItem("flutter.ls.uwuboard.tour.welcome", JSON.stringify("done"));
  });
  await openApp(page);
  await expect(page.getByRole("heading", { name: "Saved" })).toBeVisible();
});
