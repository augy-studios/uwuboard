import { expect, test } from "@playwright/test";
import { button, guestBoards, mockApi, newBoard, noErrors, openApp, skipTour, startAsGuest , said } from "./helpers.js";

test("a Timeline board starts with phases, takes a task, and switches to Kanban and back", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await mockApi(page);
  await openApp(page);
  await startAsGuest(page);
  await newBoard(page, "Launch", "Timeline");
  await skipTour(page);
  for (const phase of ["Requirements", "Design", "Build", "Test", "Release"]) await expect(page.getByRole("button", { name: new RegExp(`^${phase}\\b`) }).first()).toBeVisible();
  for (const z of ["Weeks", "Months", "Quarters"]) await expect(button(page, z)).toBeVisible();

  // A task in Design.
  await page.getByRole("button", { name: "+ Add task" }).nth(1).click();
  await page.waitForTimeout(300);
  await page.keyboard.type("Wireframes");
  await button(page, "OK").click();
  await expect(page.getByRole("button", { name: /Wireframes\s+No dates/ })).toBeVisible();
  const board = (await guestBoards(page))[0];
  expect(board.view).toBe("timeline");
  expect(board.columns[1].cards[0].title).toBe("Wireframes");

  // The Timeline's own tour, now there's a task to show it with.
  await skipTour(page);

  // The tray's view switch.
  await button(page, "Show as Kanban").click();
  await expect(said(page, "Showing as a kanban board")).toBeVisible();
  expect((await guestBoards(page))[0].view).toBe("kanban");
  await button(page, "Show as Timeline").click();
  await expect.poll(async () => (await guestBoards(page))[0].view).toBe("timeline");

  await button(page, "Weeks").click();
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem("flutter.ls.uwuboard.timeline.zoom")))).toBe("weeks");
  noErrors(page);
});
