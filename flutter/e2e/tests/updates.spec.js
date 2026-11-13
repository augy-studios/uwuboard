import { expect, test } from "@playwright/test";
import { button, calls, mockApi, noErrors, openApp, startAsGuest } from "./helpers.js";

// As announcements/release-notes-<version>.md writes them.
const notes = [
  "Checklists on the Timeline, and quicker Sync.",
  "",
  "## Download",
  "",
  "| Device | File |",
  "|---|---|",
  "| Android 7.0 or newer | `uwuboard-1.1.0.apk` |",
  "",
  "## What's new",
  "",
  "### Android app",
  "- **Checklists on the Timeline**: tick a task's steps off on its bar.",
  "- **Faster sync**",
  "",
  "### Everywhere",
  "- Fewer taps to make a board",
].join("\n");

const release = {
  version: "1.1.0",
  apk: "https://github.com/augy-studios/uwuboard/releases/download/android-v1.1.0/uwuboard-1.1.0.apk",
  size: 41000000,
  sha256: "a".repeat(64),
  page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.1.0",
  date: "2026-12-01T10:00:00Z",
  notes,
  history: [
    { version: "1.1.0", date: "2026-12-01T10:00:00Z", notes, page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.1.0" },
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
  // The newest, open by itself: its summary, then a card for each group, the Markdown read rather
  // than shown, and the download table left out.
  await expect(page.getByRole("button", { name: /^Version 1\.1\.0 v1\.1\.0 New .*3 changes/ })).toBeVisible();
  // The summary, then each group's card, read as one: its name, how many, each change.
  await expect(page.getByText("Checklists on the Timeline, and quicker Sync.")).toBeVisible();
  await expect(page.getByText(/^Android app\s+2\s+Checklists on the Timeline\s+Tick a task's steps off on its bar\.\s+Faster sync$/)).toBeVisible();
  await expect(page.getByText(/^Everywhere\s+1\s+Fewer taps to make a board$/)).toBeVisible();
  await expect(page.getByText(/\*\*|\| Device/)).toHaveCount(0);
  // This one, closed till it's pressed.
  const mine = page.getByRole("button", { name: /^Version 1\.0\.0 v1\.0\.0 Installed/ });
  await expect(mine).toBeVisible();
  await expect(page.getByText("The first uwuBoard app for Android.")).toHaveCount(0);
  await mine.click();
  await expect(page.getByText("The first uwuBoard app for Android.")).toBeVisible();
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
  // Nothing newer: this version's notes open by themselves.
  await expect(page.getByText("The first uwuBoard app for Android.")).toBeVisible();
  noErrors(page);
});

test("the Play build shows no update bar of its own", async ({ page }) => {
  await mockApi(page, { release });
  await openApp(page, "?android=1&play=1");
  await startAsGuest(page);
  await page.waitForTimeout(1500);
  await expect(page.getByText("uwuBoard 1.1.0 is out.")).toHaveCount(0);
});
