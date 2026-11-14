import { expect, test } from "@playwright/test";
import { button, fill, mockApi, noErrors, openApp, said, skipTour, stored } from "./helpers.js";

// A guest with one board of `cards` cards, past the tours. Its names must never be sent.
async function guestWithBoard(page, name, cards, query = "") {
  await page.addInitScript(([name, cards]) => {
    if (sessionStorage.getItem("seeded")) return;
    sessionStorage.setItem("seeded", "1");
    const card = (i) => ({ id: `k${i}`, title: i === 1 ? "Private card title" : `Card number ${i}`, description: "", labels: [], checklist: [], due: null, priority: null, images: [], thumbnailId: null, updatedAt: 1 });
    const board = { id: "b1", name, view: "kanban", updatedAt: 1, columns: [{ id: "c1", name: "To Do", updatedAt: 1, cards: Array.from({ length: cards }, (_, i) => card(i + 1)) }] };
    localStorage.setItem("flutter.ls.kanbanflow_guest_boards", JSON.stringify(JSON.stringify([board])));
    localStorage.setItem("flutter.ls.uwuboard.tour.welcome", JSON.stringify("done"));
    localStorage.setItem("flutter.ls.uwuboard.tour.pages", JSON.stringify('["kanban","card","timeline","newboard"]'));
  }, [name, cards]);
  await openApp(page, query);
  await button(page, "Guest").click();
  await button(page, "Continue as Guest").click();
  await expect(page.getByRole("heading", { name })).toBeVisible();
}

// Report a bug (lib/features/bug/bug_report.dart), as the site's form (main-site/js/bug-report.js).
test("Report a bug: what it adds, Screenshot a page of a card's window, sent with its ID", async ({ page }) => {
  const db = await mockApi(page);
  await guestWithBoard(page, "Secret Plans", 1, "?android=1");
  await button(page, "Report a bug").click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeVisible();
  const details = page.getByText(/^Sent with it, to help find the bug:/);
  await expect(details).toContainText("Android app");
  await expect(details).toContainText("Kanban board");
  await expect(details).not.toContainText("Secret Plans");

  // Nothing typed: asks first, sends nothing.
  await button(page, "Send").click();
  await expect(said(page, "Please say what went wrong first.")).toBeVisible();
  expect(db.bugReports ?? []).toHaveLength(0);

  await fill(page, page.getByRole("textbox", { name: /What you did/ }), "The card's due date is wrong.");
  await expect.poll(async () => JSON.parse((await stored(page, "uwuboard.bugDraft")) ?? "{}").text).toBe("The card's due date is wrong.");

  // Screenshot a page: the report goes, the bar comes, off to the card's window.
  await button(page, "Screenshot a page").click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toHaveCount(0);
  await expect(button(page, "Screenshot this page")).toBeVisible();
  await page.getByRole("button", { name: /Private card title/ }).click();
  await skipTour(page);
  await expect(button(page, "Save")).toBeVisible();
  await button(page, "Screenshot this page").click();

  // Back, with the picture and what was typed, over the card's window.
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeVisible({ timeout: 20_000 });
  await expect(button(page, "Screenshot this page")).toHaveCount(0);
  await expect(page.getByRole("img", { name: "Picture 1" })).toBeVisible();
  await expect(page.getByRole("textbox", { name: /What you did/ })).toHaveValue("The card's due date is wrong.");
  await expect(details).toContainText("Kanban board, card window");

  await button(page, "Send").click();
  await expect(said(page, "Sent as report 20261114-7K3Q. Thank you! Augy will look into it.")).toBeVisible();
  const sent = db.bugReports.at(-1);
  expect(sent.text).toBe("The card's due date is wrong.");
  expect(sent.platform).toBe("android");
  expect(sent.page).toBe("Kanban board, card window");
  expect(sent.images).toHaveLength(1);
  expect(sent.images[0]).toMatch(/^data:image\/jpeg;base64,/);
  expect(sent.full).toEqual([]);
  expect(Object.keys(sent).sort()).toEqual(["contact", "device", "full", "images", "page", "platform", "text", "version", "website"]);
  expect(JSON.stringify(sent)).not.toContain("Secret Plans");
  // Cleared once sent.
  await expect(page.getByRole("img", { name: "Picture 1" })).toHaveCount(0);
  expect(await stored(page, "uwuboard.bugDraft")).toBeNull();
  noErrors(page);
});

test("Report a bug: Screenshot a page of the board takes it whole; not set up offers email", async ({ page }) => {
  const db = await mockApi(page);
  // Enough cards that the board is taller than the screen.
  await guestWithBoard(page, "Long board", 30);
  await button(page, "Report a bug").click();
  await fill(page, page.getByRole("textbox", { name: /What you did/ }), "The whole board, please.");
  await button(page, "Screenshot a page").click();
  await button(page, "Screenshot this page").click();
  await expect(page.getByRole("img", { name: "Picture 1" })).toBeVisible({ timeout: 20_000 });

  db.bugStatus = 503;
  await button(page, "Send").click();
  await expect(said(page, "Bug reports can’t be sent from the app yet.")).toBeVisible();
  await expect(button(page, "Email it instead.")).toBeVisible();
  const sent = db.bugReports.at(-1);
  expect(sent.full).toEqual([0]);
  expect(sent.platform).toBe("web");
  // The whole board, taller than the screen, within what Telegram takes as a photo.
  const size = await page.evaluate(async (src) => {
    const i = new Image();
    i.src = src;
    await i.decode();
    return [i.naturalWidth, i.naturalHeight];
  }, sent.images[0]);
  expect(size[1]).toBeGreaterThan(915);
  expect(size[0] + size[1]).toBeLessThanOrEqual(10000);
  expect(sent.images[0].length * 0.75).toBeLessThanOrEqual(900 * 1024 + 4);
  // What's typed stays when it couldn't go.
  await expect(page.getByRole("textbox", { name: /What you did/ })).toHaveValue("The whole board, please.");
  noErrors(page);
});
