// Takes the pictures the store screenshots are made from (compose.mjs frames them): the app's real
// screens, from the browser build (../README.md), with the same seeded boards each time.
//
//     node shots/capture.mjs            with serve.mjs running; pictures land in shots/raw/
//
// Four sets: phone (412 × 892 at 3×), 7-inch tablet (600 × 1000 at 2.7×), 10-inch tablet
// (1280 × 800 at 2×) and desktop (1440 × 900 at 2×, with the desktop's title bar).
import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";

const BASE = "http://127.0.0.1:4183";
const OUT = new URL("./raw/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(OUT, { recursive: true });

// ---- the boards ----

const day = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
};

// A small picture for a card: a website mock-up in the brand's greens, as a PNG data URL.
function mockupPng(w = 480, h = 300) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      let [r, g, b] = [234, 246, 236];
      if (y < 40) [r, g, b] = [31, 107, 61];
      else if (x > 30 && x < 250 && y > 70 && y < 110) [r, g, b] = [52, 140, 84];
      else if (x > 30 && x < 330 && y > 125 && y < 140) [r, g, b] = [170, 205, 180];
      else if (x > 30 && x < 290 && y > 150 && y < 165) [r, g, b] = [170, 205, 180];
      else if (x > 30 && x < 140 && y > 190 && y < 225) [r, g, b] = [255, 179, 31];
      else if (x > 300 && x < 450 && y > 70 && y < 260) [r, g, b] = [204, 255, 204];
      const i = y * (w * 3 + 1) + 1 + x * 3;
      raw[i] = r; raw[i + 1] = g; raw[i + 2] = b;
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
  return `data:image/png;base64,${png.toString("base64")}`;
}

const card = (id, title, extra = {}) => ({ id, title, description: "", labels: [], checklist: [], due: "", priority: "", images: [], thumbnailId: null, updatedAt: 1, ...extra });
const check = (done, ...items) => items.map((text, i) => ({ text, done: i < done }));
const L = { design: { text: "Design", color: "#998dd9" }, web: { text: "Web", color: "#4c9aff" }, copy: { text: "Copy", color: "#ffb31f" }, bug: { text: "Bug", color: "#ff7452" }, home: { text: "Home", color: "#36b37e" } };

function boards() {
  const pic = mockupPng();
  return [
    {
      id: "launch", name: "Website launch", view: "kanban", updatedAt: 1, columns: [
        { id: "todo", name: "To Do", updatedAt: 1, cards: [
          card("k1", "Write the launch post", { labels: [L.copy], due: day(4), priority: "medium", checklist: check(1, "Outline", "First draft", "Edit") }),
          card("k2", "Pick the hero photo", { labels: [L.design], due: day(6) }),
          card("k3", "Set up the newsletter", { priority: "low" }),
        ] },
        { id: "doing", name: "In Progress", updatedAt: 1, cards: [
          card("k4", "Homepage redesign", { description: "New hero, three plans side by side, and a sign-up button that stays in view on phones.", labels: [L.design, L.web], due: day(1), priority: "high", images: [{ id: "img1", name: "homepage.png", data: pic }], thumbnailId: "img1", checklist: check(3, "Wireframe", "Colours", "Mobile layout", "Hand off") }),
          card("k5", "Fix the sign-up form", { labels: [L.bug], due: day(-1), priority: "urgent" }),
        ] },
        { id: "review", name: "Review", updatedAt: 1, cards: [
          card("k6", "Pricing page copy", { labels: [L.copy], checklist: check(2, "Plans", "FAQ") }),
        ] },
        { id: "done", name: "Done", updatedAt: 1, cards: [
          card("k7", "Buy the domain", { labels: [L.web], checklist: check(1, "Renew for 2 years") }),
          card("k8", "Logo files", { labels: [L.design] }),
        ] },
      ],
    },
    {
      id: "release", name: "App release", view: "timeline", updatedAt: 1, columns: [
        { id: "req", name: "Requirements", updatedAt: 1, cards: [
          card("t1", "User interviews", { start: day(-16), due: day(-10), checklist: check(3, "a", "b", "c") }),
          card("t2", "Write the spec", { start: day(-9), due: day(-5), checklist: check(2, "a", "b"), dependsOn: ["t1"] }),
        ] },
        { id: "des", name: "Design", updatedAt: 1, cards: [
          card("t3", "Wireframes", { start: day(-4), due: day(1), checklist: check(2, "a", "b", "c"), dependsOn: ["t2"] }),
          card("t4", "Visual design", { start: day(0), due: day(6), labels: [L.design], dependsOn: ["t3"] }),
        ] },
        { id: "build", name: "Build", updatedAt: 1, cards: [
          card("t5", "Sync engine", { start: day(3), due: day(12), labels: [L.web], dependsOn: ["t4"] }),
          card("t6", "Boards and cards", { start: day(8), due: day(17) }),
        ] },
        { id: "test", name: "Test", updatedAt: 1, cards: [
          card("t7", "Beta with 12 testers", { start: day(17), due: day(30), dependsOn: ["t6"] }),
        ] },
        { id: "rel", name: "Release", updatedAt: 1, cards: [
          card("t8", "Launch day", { due: day(32), milestone: true, dependsOn: ["t7"] }),
        ] },
      ],
    },
    {
      id: "home", name: "Home", view: "kanban", updatedAt: 1, columns: [
        { id: "h1", name: "This week", updatedAt: 1, cards: [card("h11", "Water the plants", { labels: [L.home], checklist: check(1, "Ferns", "Cactus") }), card("h12", "Book a dentist visit", { due: day(3) })] },
        { id: "h2", name: "Someday", updatedAt: 1, cards: [card("h21", "Paint the hallway")] },
        { id: "h3", name: "Done", updatedAt: 1, cards: [card("h31", "Fix the tap", { labels: [L.home] })] },
      ],
    },
  ];
}

const release = {
  version: "1.0.0", size: 58153064, sha256: null,
  apk: "https://github.com/augy-studios/uwuboard/releases/download/android-v1.0.0/uwuboard-1.0.0.apk",
  page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.0.0",
  date: new Date().toISOString(),
  history: [
    { version: "1.0.0", date: new Date().toISOString(), page: "https://github.com/augy-studios/uwuboard/releases/tag/android-v1.0.0",
      notes: "## What's new\n- Kanban boards and Timelines, as on the website\n- Material You by default, the UwU Apps look in Theme\n- An Updates page with every version\n- Notifications of new versions" },
  ],
};

// ---- driving the app ----

async function open(browser, { viewport, scale, query = "", seed = {} }) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: scale, hasTouch: viewport.width < 1000, isMobile: viewport.width < 1000 });
  const page = await context.newPage();
  await page.route("https://board.uwuapps.org/api/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    const body = path.endsWith("/app-release") ? release : { ok: true };
    return route.fulfill({ status: 200, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(body) });
  });
  await page.addInitScript(([b, extra]) => {
    const put = (k, v) => localStorage.setItem(`flutter.ls.${k}`, JSON.stringify(v));
    put("kanbanflow_guest_boards", JSON.stringify(b));
    put("uwuboard.tour.welcome", "done");
    put("uwuboard.tour.pages", JSON.stringify(["kanban", "timeline", "card", "newboard"]));
    put("uwuboard.trayOpen", "1");
    for (const [k, v] of Object.entries(extra)) put(k, v);
  }, [boards(), seed]);
  await page.goto(`${BASE}/${query}`);
  return { context, page };
}

const btn = (page, name, exact = true) => page.getByRole("button", { name, exact });

async function guest(page) {
  await btn(page, "Guest").click();
  await btn(page, "Continue as Guest").click();
  await page.getByRole("heading", { name: "Website launch" }).waitFor();
}

async function board(page, name) {
  const wide = (page.viewportSize()?.width ?? 0) > 720;
  if (!wide) await btn(page, "Boards").click();
  await page.getByRole("button", { name, exact: true }).last().click();
  await page.getByRole("heading", { name }).waitFor();
  await page.waitForTimeout(500);
}

async function shot(page, file) {
  await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}${file}.png` });
  console.log(file);
}

// The eight screens, in the order the store shows them.
async function screens(browser, set, viewport, scale, extraQuery = "") {
  const q = (s) => `?android=1${s}${extraQuery}`;
  let { context, page } = await open(browser, { viewport, scale, query: q("&wallpaper=1"), seed: { "app.look": "uwuapps" } });
  await guest(page);
  await shot(page, `${set}-01-board`);

  await board(page, "App release");
  await shot(page, `${set}-02-timeline`);

  await board(page, "Website launch");
  await page.getByRole("button", { name: /^Homepage redesign/ }).click();
  await page.getByText("Description").first().waitFor();
  await shot(page, `${set}-03-card`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q("&wallpaper=1"), seed: { "app.look": "material" } }));
  await guest(page);
  await shot(page, `${set}-04-material-you`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q(""), seed: { "app.look": "uwuapps", "uwuboard.colorTheme": "not-green-4" } }));
  await guest(page);
  await btn(page, "Theme: colour, light or dark").click();
  await page.getByRole("heading", { name: "Theme" }).waitFor();
  await shot(page, `${set}-05-theme`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q(""), seed: { "app.look": "uwuapps" } }));
  await guest(page);
  await btn(page, "Sync with another device").click();
  await btn(page, "Show a code on this device").click();
  await page.waitForTimeout(2500);
  await shot(page, `${set}-06-sync`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q("&wallpaper=1"), seed: { "app.look": "material" } }));
  await guest(page);
  if (viewport.width <= 720) await btn(page, "Boards").click();
  await page.getByRole("button", { name: /^Updates/ }).click();
  await page.getByText("Every version").waitFor();
  await shot(page, `${set}-07-updates`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q(""), seed: { "app.look": "uwuapps", "uwuboard.mode": "dark", "uwuboard.tour.pages": JSON.stringify(["timeline", "card", "newboard"]) } }));
  await guest(page);
  await page.getByRole("button", { name: "Skip" }).waitFor({ timeout: 8000 });
  await shot(page, `${set}-08-dark-tour`);
  await context.close();
}

async function desktop(browser) {
  const viewport = { width: 1440, height: 900 };
  const scale = 2;
  const q = "?desktop=1";
  let { context, page } = await open(browser, { viewport, scale, query: q, seed: { "app.look": "uwuapps" } });
  await guest(page);
  await shot(page, "desktop-01-board");

  await board(page, "App release");
  await shot(page, "desktop-02-timeline");

  // The command bar, in the middle of the 40 px title bar.
  const pass = await page.addStyleTag({ content: "flt-semantics-host, flt-semantics { pointer-events: none !important; }" });
  await page.mouse.click(viewport.width / 2, 20);
  await pass.evaluate((e) => e.remove());
  await page.waitForTimeout(500);
  await page.keyboard.type("design");
  await page.waitForTimeout(400);
  await shot(page, "desktop-03-command");
  await page.keyboard.press("Escape");

  await board(page, "Website launch");
  await page.getByRole("button", { name: /^Homepage redesign/ }).click();
  await page.getByText("Description").first().waitFor();
  await shot(page, "desktop-04-card");
  await page.keyboard.press("Escape");
  await page.waitForTimeout(400);

  // The screen reader's layer takes a right-click; this one goes to the canvas under it.
  const box = await page.getByRole("button", { name: "App release", exact: true }).last().boundingBox();
  const pass2 = await page.addStyleTag({ content: "flt-semantics-host, flt-semantics { pointer-events: none !important; }" });
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2, { button: "right" });
  await pass2.evaluate((e) => e.remove());
  await page.waitForTimeout(800);
  await shot(page, "desktop-05-menu");
  await page.keyboard.press("Escape");
  await context.close();

  ({ context, page } = await open(browser, { viewport: { width: 940, height: 660 }, scale, query: "?welcome=1", seed: { "uwuboard.colorTheme": "classic" } }));
  await page.getByText("Get started").waitFor();
  await shot(page, "desktop-06-welcome");
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q, seed: { "app.look": "uwuapps", "uwuboard.mode": "dark", "uwuboard.colorTheme": "not-green-2" } }));
  await guest(page);
  await board(page, "App release");
  await shot(page, "desktop-07-dark");
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: q, seed: { "app.look": "uwuapps" } }));
  await guest(page);
  await btn(page, "Sync with another device").click();
  await btn(page, "Show a code on this device").click();
  await page.waitForTimeout(2500);
  await shot(page, "desktop-08-sync");
  await context.close();
}

const browser = await chromium.launch();
const only = process.argv[2];
try {
  if (!only || only === "phone") await screens(browser, "phone", { width: 412, height: 892 }, 3);
  if (!only || only === "tablet7") await screens(browser, "tablet7", { width: 600, height: 1000 }, 2.7);
  if (!only || only === "tablet10") await screens(browser, "tablet10", { width: 1280, height: 800 }, 2);
  if (!only || only === "desktop") await desktop(browser);
} finally {
  await browser.close();
}
