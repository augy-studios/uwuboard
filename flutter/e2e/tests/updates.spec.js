import { expect, test } from "@playwright/test";
import { button, calls, mockApi, noErrors, openApp, startAsGuest } from "./helpers.js";

const release = {
  version: "1.1.0",
  apk: "https://github.com/augy-studios/uwuboard/releases/download/android-v1.1.0/uwuboard-1.1.0.apk",
  size: 41000000,
  sha256: "a".repeat(64),
  page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.1.0",
  date: "2026-12-01T10:00:00Z",
  notes: "## What's new\n- Checklists on the Timeline\n- Faster sync",
  history: [
    { version: "1.1.0", date: "2026-12-01T10:00:00Z", notes: "## What's new\n- Checklists on the Timeline\n- Faster sync", page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.1.0" },
    { version: "1.0.0", date: "2026-11-14T10:00:00Z", notes: "The first uwuBoard app for Android.", page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.0.0" },
  ],
};

test("a newer version shows a bar; the Updates page lists every version and joins release notifications", async ({ page }) => {
  await mockApi(page, { release });
  await openApp(page, "?android=1&wallpaper=1");
  await startAsGuest(page);
  await expect(page.getByText("uwuBoard 1.1.0 is out.")).toBeVisible();
  await button(page, "Update").click();

  await expect(page.getByRole("group", { name: /^uwuBoard 1\.1\.0 is out This is version 1\.0\.0\./ })).toBeVisible();
  await expect(page.getByText("Every version")).toBeVisible();
  await expect(page.getByRole("group", { name: /Checklists on the Timeline/ })).toBeVisible();
  await expect(page.getByRole("group", { name: /The first uwuBoard app for Android\./ })).toBeVisible();
  await expect(page.getByRole("group", { name: /^1\.0\.0 Installed/ })).toBeVisible();
  await expect(page.getByRole("group", { name: /^1\.1\.0 New/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /Update \(41\.0 MB\)/ })).toBeVisible();

  await page.getByRole("switch", { name: /New versions of the app/ }).click();
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "setReleases")?.options).toEqual({ on: true });
  noErrors(page);
});

test("up to date, the Updates page says so and still lists the versions", async ({ page }) => {
  await mockApi(page, { release: { ...release, version: "1.0.0", history: release.history.slice(1) } });
  await openApp(page, "?android=1");
  await startAsGuest(page);
  await expect(page.getByText("uwuBoard 1.1.0 is out.")).toHaveCount(0);
  await page.getByRole("button", { name: "Boards" }).click();
  await page.getByRole("button", { name: /Updates · 1\.0\.0/ }).click();
  await expect(page.getByRole("group", { name: /^You’re up to date/ })).toBeVisible();
  await expect(page.getByRole("group", { name: /The first uwuBoard app for Android\./ })).toBeVisible();
  noErrors(page);
});

test("the Play build shows no update bar of its own", async ({ page }) => {
  await mockApi(page, { release });
  await openApp(page, "?android=1&play=1");
  await startAsGuest(page);
  await page.waitForTimeout(1500);
  await expect(page.getByText("uwuBoard 1.1.0 is out.")).toHaveCount(0);
});
