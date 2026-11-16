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

const BASE_URL = "http://127.0.0.1:4183";
const OUTPUT_FOLDER = new URL("./raw/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(OUTPUT_FOLDER, { recursive: true });

// ---- the boards ----

// The date this many days from today (negative for the past), as YYYY-MM-DD.
const daysFromNow = (dayCount) => {
  const date = new Date();
  date.setDate(date.getDate() + dayCount);
  return date.toISOString().slice(0, 10);
};

// A small picture for a card: a website mock-up in the brand's greens, as a PNG data URL.
// It is built by hand: each row of pixels is filled in colour by colour, then wrapped in the
// PNG file format (a signature followed by IHDR, IDAT and IEND chunks).
function mockupPng(width = 480, height = 300) {
  // One filter byte (0) at the start of each row, then three bytes (red, green, blue) per pixel.
  const rawPixels = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y = y + 1) {
    rawPixels[y * (width * 3 + 1)] = 0;
    for (let x = 0; x < width; x = x + 1) {
      // The page's pale background, with a header bar, a heading, two lines of text, a button
      // and a picture drawn over it.
      let [red, green, blue] = [234, 246, 236];
      if (y < 40) {
        [red, green, blue] = [31, 107, 61];
      } else if (x > 30 && x < 250 && y > 70 && y < 110) {
        [red, green, blue] = [52, 140, 84];
      } else if (x > 30 && x < 330 && y > 125 && y < 140) {
        [red, green, blue] = [170, 205, 180];
      } else if (x > 30 && x < 290 && y > 150 && y < 165) {
        [red, green, blue] = [170, 205, 180];
      } else if (x > 30 && x < 140 && y > 190 && y < 225) {
        [red, green, blue] = [255, 179, 31];
      } else if (x > 300 && x < 450 && y > 70 && y < 260) {
        [red, green, blue] = [204, 255, 204];
      }
      const pixelIndex = y * (width * 3 + 1) + 1 + x * 3;
      rawPixels[pixelIndex] = red;
      rawPixels[pixelIndex + 1] = green;
      rawPixels[pixelIndex + 2] = blue;
    }
  }
  // One PNG chunk: its length, its type and data, then a checksum of the type and data.
  const pngChunk = (type, data) => {
    const lengthBytes = Buffer.alloc(4);
    lengthBytes.writeUInt32BE(data.length);
    const typeAndData = Buffer.concat([Buffer.from(type), data]);
    const checksumBytes = Buffer.alloc(4);
    checksumBytes.writeUInt32BE(crc32(typeAndData) >>> 0);
    return Buffer.concat([lengthBytes, typeAndData, checksumBytes]);
  };
  // The image header: width, height, 8 bits per colour, colour type 2 (red, green, blue).
  const imageHeader = Buffer.alloc(13);
  imageHeader.writeUInt32BE(width, 0);
  imageHeader.writeUInt32BE(height, 4);
  imageHeader[8] = 8;
  imageHeader[9] = 2;
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk("IHDR", imageHeader), pngChunk("IDAT", deflateSync(rawPixels)), pngChunk("IEND", Buffer.alloc(0))]);
  return `data:image/png;base64,${png.toString("base64")}`;
}

// A card with every field the app saves, plus whatever is in `extra`.
const card = (id, title, extra = {}) => {
  return { id, title, description: "", labels: [], checklist: [], due: "", priority: "", images: [], thumbnailId: null, updatedAt: 1, ...extra };
};
// A checklist of these items where the first `doneCount` are ticked.
const makeChecklist = (doneCount, ...items) => {
  return items.map((text, index) => {
    return { text, done: index < doneCount };
  });
};
const LABELS = { design: { text: "Design", color: "#998dd9" }, web: { text: "Web", color: "#4c9aff" }, copy: { text: "Copy", color: "#ffb31f" }, bug: { text: "Bug", color: "#ff7452" }, home: { text: "Home", color: "#36b37e" } };

// The three boards every screenshot starts with: a Kanban board, a Timeline and a small home board.
function boards() {
  const mockupPicture = mockupPng();
  return [
    {
      id: "launch", name: "Website launch", view: "kanban", updatedAt: 1, columns: [
        { id: "todo", name: "To Do", updatedAt: 1, cards: [
          card("k1", "Write the launch post", { labels: [LABELS.copy], due: daysFromNow(4), priority: "medium", checklist: makeChecklist(1, "Outline", "First draft", "Edit") }),
          card("k2", "Pick the hero photo", { labels: [LABELS.design], due: daysFromNow(6) }),
          card("k3", "Set up the newsletter", { priority: "low" }),
        ] },
        { id: "doing", name: "In Progress", updatedAt: 1, cards: [
          card("k4", "Homepage redesign", { description: "New hero, three plans side by side, and a sign-up button that stays in view on phones.", labels: [LABELS.design, LABELS.web], due: daysFromNow(1), priority: "high", images: [{ id: "img1", name: "homepage.png", data: mockupPicture }], thumbnailId: "img1", checklist: makeChecklist(3, "Wireframe", "Colours", "Mobile layout", "Hand off") }),
          card("k5", "Fix the sign-up form", { labels: [LABELS.bug], due: daysFromNow(-1), priority: "urgent" }),
        ] },
        { id: "review", name: "Review", updatedAt: 1, cards: [
          card("k6", "Pricing page copy", { labels: [LABELS.copy], checklist: makeChecklist(2, "Plans", "FAQ") }),
        ] },
        { id: "done", name: "Done", updatedAt: 1, cards: [
          card("k7", "Buy the domain", { labels: [LABELS.web], checklist: makeChecklist(1, "Renew for 2 years") }),
          card("k8", "Logo files", { labels: [LABELS.design] }),
        ] },
      ],
    },
    {
      id: "release", name: "App release", view: "timeline", updatedAt: 1, columns: [
        { id: "req", name: "Requirements", updatedAt: 1, cards: [
          card("t1", "User interviews", { start: daysFromNow(-16), due: daysFromNow(-10), checklist: makeChecklist(3, "a", "b", "c") }),
          card("t2", "Write the spec", { start: daysFromNow(-9), due: daysFromNow(-5), checklist: makeChecklist(2, "a", "b"), dependsOn: ["t1"] }),
        ] },
        { id: "des", name: "Design", updatedAt: 1, cards: [
          card("t3", "Wireframes", { start: daysFromNow(-4), due: daysFromNow(1), checklist: makeChecklist(2, "a", "b", "c"), dependsOn: ["t2"] }),
          card("t4", "Visual design", { start: daysFromNow(0), due: daysFromNow(6), labels: [LABELS.design], dependsOn: ["t3"] }),
        ] },
        { id: "build", name: "Build", updatedAt: 1, cards: [
          card("t5", "Sync engine", { start: daysFromNow(3), due: daysFromNow(12), labels: [LABELS.web], dependsOn: ["t4"] }),
          card("t6", "Boards and cards", { start: daysFromNow(8), due: daysFromNow(17) }),
        ] },
        { id: "test", name: "Test", updatedAt: 1, cards: [
          card("t7", "Beta with 12 testers", { start: daysFromNow(17), due: daysFromNow(30), dependsOn: ["t6"] }),
        ] },
        { id: "rel", name: "Release", updatedAt: 1, cards: [
          card("t8", "Launch day", { due: daysFromNow(32), milestone: true, dependsOn: ["t7"] }),
        ] },
      ],
    },
    {
      id: "home", name: "Home", view: "kanban", updatedAt: 1, columns: [
        { id: "h1", name: "This week", updatedAt: 1, cards: [card("h11", "Water the plants", { labels: [LABELS.home], checklist: makeChecklist(1, "Ferns", "Cactus") }), card("h12", "Book a dentist visit", { due: daysFromNow(3) })] },
        { id: "h2", name: "Someday", updatedAt: 1, cards: [card("h21", "Paint the hallway")] },
        { id: "h3", name: "Done", updatedAt: 1, cards: [card("h31", "Fix the tap", { labels: [LABELS.home] })] },
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

// Opens the app in a new browser window of this size, with its API answered here and the boards
// above (plus the settings in `seed`) already saved, as if the app had been used before.
async function openPage(browser, { viewport, scale, query = "", seed = {} }) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: scale, hasTouch: viewport.width < 1000, isMobile: viewport.width < 1000 });
  const page = await context.newPage();
  await page.route("https://board.uwuapps.org/api/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    let body;
    if (path.endsWith("/app-release")) {
      body = release;
    } else {
      body = { ok: true };
    }
    return route.fulfill({ status: 200, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(body) });
  });
  // Runs in the browser before the app starts: saves the boards and settings where the app reads them.
  await page.addInitScript(([savedBoards, extraSettings]) => {
    const put = (key, value) => {
      localStorage.setItem(`flutter.ls.${key}`, JSON.stringify(value));
    };
    put("kanbanflow_guest_boards", JSON.stringify(savedBoards));
    put("uwuboard.tour.welcome", "done");
    put("uwuboard.tour.pages", JSON.stringify(["kanban", "timeline", "card", "newboard"]));
    put("uwuboard.trayOpen", "1");
    for (const [key, value] of Object.entries(extraSettings)) {
      put(key, value);
    }
  }, [boards(), seed]);
  await page.goto(`${BASE_URL}/${query}`);
  return { context, page };
}

// The button with this name (matched exactly unless `exact` is false).
const button = (page, name, exact = true) => {
  return page.getByRole("button", { name, exact });
};

// Goes in as a guest and waits for the first board.
async function continueAsGuest(page) {
  await button(page, "Guest").click();
  await button(page, "Continue as Guest").click();
  await page.getByRole("heading", { name: "Website launch" }).waitFor();
}

// Opens the board with this name. On a narrow screen the board list has to be opened first.
async function openBoard(page, name) {
  let viewportWidth = 0;
  const viewportSize = page.viewportSize();
  if (viewportSize !== null && viewportSize !== undefined && viewportSize.width !== null && viewportSize.width !== undefined) {
    viewportWidth = viewportSize.width;
  }
  const wide = viewportWidth > 720;
  if (!wide) {
    await button(page, "Boards").click();
  }
  await page.getByRole("button", { name, exact: true }).last().click();
  await page.getByRole("heading", { name }).waitFor();
  await page.waitForTimeout(500);
}

// Waits for the screen to settle, then saves a screenshot as raw/<fileName>.png.
async function takeScreenshot(page, fileName) {
  await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUTPUT_FOLDER}${fileName}.png` });
  console.log(fileName);
}

// The eight screens, in the order the store shows them.
async function screens(browser, setName, viewport, scale, extraQuery = "") {
  // The query that draws the app as Android does, with these extra parameters.
  const queryFor = (extraParameters) => {
    return `?android=1${extraParameters}${extraQuery}`;
  };
  let { context, page } = await openPage(browser, { viewport, scale, query: queryFor("&wallpaper=1"), seed: { "app.look": "uwuapps" } });
  await continueAsGuest(page);
  await takeScreenshot(page, `${setName}-01-board`);

  await openBoard(page, "App release");
  await takeScreenshot(page, `${setName}-02-timeline`);

  await openBoard(page, "Website launch");
  await page.getByRole("button", { name: /^Homepage redesign/ }).click();
  await page.getByText("Description").first().waitFor();
  await takeScreenshot(page, `${setName}-03-card`);
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: queryFor("&wallpaper=1"), seed: { "app.look": "material" } }));
  await continueAsGuest(page);
  await takeScreenshot(page, `${setName}-04-material-you`);
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: queryFor(""), seed: { "app.look": "uwuapps", "uwuboard.colorTheme": "not-green-4" } }));
  await continueAsGuest(page);
  await button(page, "Theme: colour, light or dark").click();
  await page.getByRole("heading", { name: "Theme" }).waitFor();
  await takeScreenshot(page, `${setName}-05-theme`);
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: queryFor(""), seed: { "app.look": "uwuapps" } }));
  await continueAsGuest(page);
  await button(page, "Sync with another device").click();
  await button(page, "Show a code on this device").click();
  await page.waitForTimeout(2500);
  await takeScreenshot(page, `${setName}-06-sync`);
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: queryFor("&wallpaper=1"), seed: { "app.look": "material" } }));
  await continueAsGuest(page);
  if (viewport.width <= 720) {
    await button(page, "Boards").click();
  }
  await page.getByRole("button", { name: /^Updates/ }).click();
  await page.getByText("Every version").waitFor();
  await takeScreenshot(page, `${setName}-07-updates`);
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: queryFor(""), seed: { "app.look": "uwuapps", "uwuboard.mode": "dark", "uwuboard.tour.pages": JSON.stringify(["timeline", "card", "newboard"]) } }));
  await continueAsGuest(page);
  await page.getByRole("button", { name: "Skip" }).waitFor({ timeout: 8000 });
  await takeScreenshot(page, `${setName}-08-dark-tour`);
  await context.close();
}

// The eight desktop screens, drawn with the desktop's title bar, plus its welcome window.
async function desktop(browser) {
  const viewport = { width: 1440, height: 900 };
  const scale = 2;
  const desktopQuery = "?desktop=1";
  let { context, page } = await openPage(browser, { viewport, scale, query: desktopQuery, seed: { "app.look": "uwuapps" } });
  await continueAsGuest(page);
  await takeScreenshot(page, "desktop-01-board");

  await openBoard(page, "App release");
  await takeScreenshot(page, "desktop-02-timeline");

  // The command bar, in the middle of the 40 px title bar.
  const clickThroughStyle = await page.addStyleTag({ content: "flt-semantics-host, flt-semantics { pointer-events: none !important; }" });
  await page.mouse.click(viewport.width / 2, 20);
  await clickThroughStyle.evaluate((element) => {
    element.remove();
  });
  await page.waitForTimeout(500);
  await page.keyboard.type("design");
  await page.waitForTimeout(400);
  await takeScreenshot(page, "desktop-03-command");
  await page.keyboard.press("Escape");

  await openBoard(page, "Website launch");
  await page.getByRole("button", { name: /^Homepage redesign/ }).click();
  await page.getByText("Description").first().waitFor();
  await takeScreenshot(page, "desktop-04-card");
  await page.keyboard.press("Escape");
  await page.waitForTimeout(400);

  // The screen reader's layer takes a right-click; this one goes to the canvas under it.
  const boardButtonBox = await page.getByRole("button", { name: "App release", exact: true }).last().boundingBox();
  const secondClickThroughStyle = await page.addStyleTag({ content: "flt-semantics-host, flt-semantics { pointer-events: none !important; }" });
  await page.mouse.click(boardButtonBox.x + boardButtonBox.width / 2, boardButtonBox.y + boardButtonBox.height / 2, { button: "right" });
  await secondClickThroughStyle.evaluate((element) => {
    element.remove();
  });
  await page.waitForTimeout(800);
  await takeScreenshot(page, "desktop-05-menu");
  await page.keyboard.press("Escape");
  await context.close();

  ({ context, page } = await openPage(browser, { viewport: { width: 940, height: 660 }, scale, query: "?welcome=1", seed: { "uwuboard.colorTheme": "classic" } }));
  await page.getByText("Get started").waitFor();
  await takeScreenshot(page, "desktop-06-welcome");
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: desktopQuery, seed: { "app.look": "uwuapps", "uwuboard.mode": "dark", "uwuboard.colorTheme": "not-green-2" } }));
  await continueAsGuest(page);
  await openBoard(page, "App release");
  await takeScreenshot(page, "desktop-07-dark");
  await context.close();

  ({ context, page } = await openPage(browser, { viewport, scale, query: desktopQuery, seed: { "app.look": "uwuapps" } }));
  await continueAsGuest(page);
  await button(page, "Sync with another device").click();
  await button(page, "Show a code on this device").click();
  await page.waitForTimeout(2500);
  await takeScreenshot(page, "desktop-08-sync");
  await context.close();
}

// Takes every set, or only the one named on the command line (phone, tablet7, tablet10 or desktop).
const browser = await chromium.launch();
const onlySet = process.argv[2];
try {
  if (!onlySet || onlySet === "phone") {
    await screens(browser, "phone", { width: 412, height: 892 }, 3);
  }
  if (!onlySet || onlySet === "tablet7") {
    await screens(browser, "tablet7", { width: 600, height: 1000 }, 2.7);
  }
  if (!onlySet || onlySet === "tablet10") {
    await screens(browser, "tablet10", { width: 1280, height: 800 }, 2);
  }
  if (!onlySet || onlySet === "desktop") {
    await desktop(browser);
  }
} finally {
  await browser.close();
}
