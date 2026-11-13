import { expect, test } from "@playwright/test";
import { button, calls, mockApi, newBoard, noErrors, openApp, skipTour, startAsGuest , said } from "./helpers.js";

test("Export saves the board as the site's board file, into Downloads on Android", async ({ page }) => {
  await mockApi(page);
  await openApp(page, "?android=1");
  await startAsGuest(page);
  await newBoard(page, "Trip planning");
  await skipTour(page);
  await button(page, "Export this board to a file").click();
  await expect(said(page, "Board exported")).toBeVisible();
  const save = (await calls(page)).find((c) => c.method === "saveFile");
  expect(save.options.name).toBe("Trip_planning_kanban.json");
  expect(save.options.mime).toBe("application/json");
  const file = JSON.parse(Buffer.from(save.options.data, "base64").toString("utf8"));
  expect(file).toMatchObject({ name: "Trip planning", view: "kanban" });
  expect(file.columns).toHaveLength(3);
  noErrors(page);
});

test("Sync checks the code before connecting", async ({ page }) => {
  await mockApi(page);
  await openApp(page);
  await startAsGuest(page);
  await button(page, "Sync with another device").click();
  await expect(page.getByRole("heading", { name: "Sync with another device" })).toBeVisible();
  await page.getByRole("textbox").first().click();
  await page.waitForTimeout(300);
  await page.keyboard.type("ABC");
  await button(page, "Connect").click();
  await expect(said(page, "The code is the 6 letters and numbers on the other device’s screen.")).toBeVisible();
  noErrors(page);
});
