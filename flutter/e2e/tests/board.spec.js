import { expect, test } from "@playwright/test";
import { button, fill, guestBoards, mockApi, newBoard, noErrors, openApp, skipTour, startAsGuest , said } from "./helpers.js";

test("a guest makes a Kanban board, adds a card and edits it, kept as the site keeps it", async ({ page }) => {
  await mockApi(page);
  await openApp(page);
  await startAsGuest(page);

  await newBoard(page, "Sprint 67");
  await skipTour(page);
  for (const col of ["To Do", "In Progress", "Done"]) await expect(page.getByText(col, { exact: true }).first()).toBeVisible();

  // A card in To Do.
  await button(page, "Add card").first().click();
  await page.waitForTimeout(300);
  await page.keyboard.type("Write the release notes");
  await button(page, "Add").click();
  await expect(page.getByText("Write the release notes")).toBeVisible();

  // Its details.
  await page.getByRole("button", { name: /Write the release notes/ }).click();
  await skipTour(page);
  const desc = page.getByRole("textbox", { name: /Add a description/ });
  await fill(page, desc, "For GitHub and Telegram");
  await button(page, "Save").click();
  await expect(said(page, "Card saved")).toBeVisible();

  // Stored under the site's key, in the site's shape.
  const boards = await guestBoards(page);
  expect(boards).toHaveLength(1);
  const b = boards[0];
  expect(b).toMatchObject({ name: "Sprint 67", view: "kanban" });
  expect(b.columns.map((c) => c.name)).toEqual(["To Do", "In Progress", "Done"]);
  const card = b.columns[0].cards[0];
  expect(card).toMatchObject({ title: "Write the release notes", description: "For GitHub and Telegram", labels: [], checklist: [], due: "", priority: "", images: [] });
  expect(typeof card.updatedAt).toBe("number");
  expect(card.id).toMatch(/^[a-z0-9]+$/);
  noErrors(page);
});

test("a board kept from before comes back as a guest, and can be renamed and deleted", async ({ page }) => {
  await mockApi(page);
  await page.addInitScript(() => {
    if (sessionStorage.getItem("seeded")) return;
    sessionStorage.setItem("seeded", "1");
    const board = { id: "b1", name: "Home", view: "kanban", updatedAt: 1, columns: [{ id: "c1", name: "To Do", updatedAt: 1, cards: [{ id: "k1", title: "Water the plants", description: "", labels: [{ text: "Garden", color: "#36b37e" }], checklist: [{ text: "Ferns", done: true }, { text: "Cactus", done: false }], due: "2026-01-02", priority: "high", images: [], thumbnailId: null, updatedAt: 1 }] }] };
    localStorage.setItem("flutter.ls.kanbanflow_guest_boards", JSON.stringify(JSON.stringify([board])));
    localStorage.setItem("flutter.ls.uwuboard.tour.welcome", JSON.stringify("done"));
    localStorage.setItem("flutter.ls.uwuboard.tour.pages", JSON.stringify('["kanban","card","timeline","newboard"]'));
  });
  await openApp(page);
  await button(page, "Guest").click();
  await button(page, "Continue as Guest").click();
  await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();
  // One node per card for a screen reader, saying what's on it.
  await expect(page.getByRole("button", { name: "Water the plants, Garden, due 2026-01-02, overdue, high priority, 1 of 2 done" })).toBeVisible();

  await button(page, "Rename board").click();
  await page.waitForTimeout(300);
  await page.keyboard.press("Control+A");
  await page.keyboard.type("Home jobs");
  await button(page, "OK").click();
  await expect(page.getByRole("heading", { name: "Home jobs" })).toBeVisible();
  expect((await guestBoards(page))[0].name).toBe("Home jobs");

  await button(page, "Delete this board").click();
  await button(page, "Delete").click();
  await expect(page.getByText("Select or create a board to get started")).toBeVisible();
  expect(await guestBoards(page)).toEqual([]);
  noErrors(page);
});
