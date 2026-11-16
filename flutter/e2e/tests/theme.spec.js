import { expect, test } from "@playwright/test";
import { button, mockApi, noErrors, openApp, startAsGuest, stored } from "./helpers.js";

test("off Android, the site's look: light, dark and the brand colours, under the site's keys", async ({ page }) => {
  await mockApi(page);
  await openApp(page);
  await startAsGuest(page);
  await button(page, "Theme: colour, light or dark").click();
  await expect(page.getByRole("heading", { name: "Theme" })).toBeVisible();
  await button(page, "Dark").click();
  await expect.poll(() => stored(page, "uwuboard.mode")).toBe("dark");
  await button(page, "Not green 2").click();
  await expect.poll(() => stored(page, "uwuboard.colorTheme")).toBe("not-green-2");
  await button(page, "Time-based").click();
  await expect(page.getByText(/Following the clock\. Currently (light|dark)\./)).toBeVisible();
  noErrors(page);
});

test("on Android with wallpaper colours, Material You is the default, and the UwU Apps look a switch away", async ({ page }) => {
  await mockApi(page);
  await openApp(page, "?android=1&wallpaper=1");
  await startAsGuest(page);
  await button(page, "Theme: colour, light or dark").click();
  await expect(page.getByText("Colours and fonts from your device.")).toBeVisible();
  // Material You has no brand swatches.
  await expect(button(page, "Classic")).toHaveCount(0);
  await button(page, "UwU Apps").click();
  await expect.poll(() => stored(page, "app.look")).toBe("uwuapps");
  await expect(button(page, "Classic")).toBeVisible();
  await button(page, "Material You").click();
  await expect.poll(() => stored(page, "app.look")).toBe("material");
  noErrors(page);
});

// The desktop tests don't call noErrors: drawn as the desktop in a headless browser, Flutter's
// focus traversal throws "RenderBox was not laid out" as the page takes focus, with any look.
test("on the desktop, the second look is the system's glass in place of Material You", async ({ page }) => {
  await mockApi(page);
  await openApp(page, "?desktop=1&glass=fluent");
  await startAsGuest(page);
  await button(page, "Theme: colour, light or dark").click();
  await expect(page.getByRole("heading", { name: "Theme" })).toBeVisible();
  await expect(button(page, "Material You")).toHaveCount(0);
  await button(page, "Fluent 2").click();
  await expect.poll(() => stored(page, "app.look")).toBe("native");
  await expect(page.getByText(/Windows 11’s Fluent 2: Mica behind the window and Acrylic/)).toBeVisible();
  // The system's accent, not the brand swatches.
  await expect(button(page, "Classic")).toHaveCount(0);
  await expect(page.getByText("Use system accent colour")).toHaveCount(0);
  await button(page, "UwU Apps").click();
  await expect.poll(() => stored(page, "app.look")).toBe("uwuapps");
  await expect(button(page, "Classic")).toBeVisible();
});

for (const [glass, label, note] of [
  ["tahoe", "macOS Tahoe", /The glass of macOS Tahoe/],
  ["frosted", "Frosted Glass", /The frosted glass of Deepin \(DDE\) and COSMIC/],
]) {
  test(`on ${label}'s desktop, its own glass`, async ({ page }) => {
    await mockApi(page);
    await openApp(page, `?desktop=1&glass=${glass}`);
    await startAsGuest(page);
    await button(page, "Theme: colour, light or dark").click();
    await button(page, label).click();
    await expect(page.getByText(note)).toBeVisible();
    });
}
