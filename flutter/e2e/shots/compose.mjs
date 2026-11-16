// Frames the pictures from capture.mjs as store screenshots, in the style SG Bus Timings' have:
// a deep coloured page, a headline in Jua, the app in a phone, tablet or window, and handwritten
// notes with arrows to what they're about. Each number has its own colour (`themes`), the same
// on the phone, tablet and desktop ones. Writes them into docs/:
//
//   docs/phone-assets/01…08.png            1620 × 2880
//   docs/tablet-assets/7-inch/01…08.png    1620 × 2880
//   docs/tablet-assets/10-inch/01…08.png   2880 × 1620
//   docs/desktop-assets/01…08.png          2880 × 1620
//   docs/feature-graphic.png               1024 × 500
//
//     node shots/compose.mjs
import { chromium } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const thisFolder = dirname(fileURLToPath(import.meta.url));
// The file URL of one of capture.mjs's pictures in shots/raw/.
const rawPictureUrl = (fileName) => {
  return pathToFileURL(join(thisFolder, "raw", `${fileName}.png`)).href;
};
const docsFolder = join(thisFolder, "../../../docs");
const juaFontUrl = pathToFileURL(join(thisFolder, "../../assets/fonts/Jua-Regular.ttf")).href;
const iconUrl = pathToFileURL(join(thisFolder, "../../assets/images/icon-512.png")).href;

// What each picture says. `to` is where an arrow points, as a fraction of the screen it's on.
const portraitScreens = [
  { file: "01-board", raw: "01-board", head: "Your to-dos,<br>on a board.", notes: [{ text: "Drag cards from<br>To Do to Done", side: "l", y: 0.42, to: [0.3, 0.22] }, { text: "Every action in<br>the edge tray", side: "r", y: 0.62, to: [0.9, 0.2] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Or lay them out<br>on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.62, to: [0.62, 0.27] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.78, to: [0.82, 0.36] }] },
  { file: "03-card", raw: "03-card", head: "Everything<br>on the card.", notes: [{ text: "Pictures, labels<br>and checklists", side: "l", y: 0.66, to: [0.18, 0.62] }, { text: "A due date and<br>a priority", side: "r", y: 0.42, to: [0.82, 0.38] }] },
  { file: "04-material-you", raw: "04-material-you", head: "In your phone's<br>colours.", notes: [{ text: "Material You,<br>by default", side: "l", y: 0.4, to: [0.3, 0.22] }, { text: "From your<br>wallpaper", side: "r", y: 0.6, to: [0.6, 0.3] }] },
  { file: "05-theme", raw: "05-theme", head: "Or uwuBoard's<br>own look.", notes: [{ text: "Seven brand<br>colours", side: "l", y: 0.7, to: [0.35, 0.96] }, { text: "Light, dark, or<br>by the clock", side: "r", y: 0.6, to: [0.7, 0.9] }] },
  { file: "06-sync", raw: "06-sync", head: "Sync without<br>an account.", notes: [{ text: "Scan it with your<br>other device", side: "l", y: 0.66, to: [0.38, 0.84] }, { text: "Straight from one<br>to the other", side: "r", y: 0.46, to: [0.62, 0.77] }] },
  { file: "07-updates", raw: "07-updates", head: "Always<br>up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.66, to: [0.3, 0.83] }, { text: "A note when a<br>new one's out", side: "r", y: 0.48, to: [0.88, 0.71] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around<br>the first time.", notes: [{ text: "One step<br>at a time", side: "l", y: 0.5, to: [0.4, 0.78] }, { text: "Dark when<br>you like", side: "r", y: 0.34, to: [0.62, 0.1] }] },
];

const landscapeScreens = [
  { file: "01-board", raw: "01-board", head: "Your to-dos, on a board.", notes: [{ text: "Drag cards from<br>To Do to Done", side: "l", y: 0.42, to: [0.32, 0.28] }, { text: "Every action in<br>the edge tray", side: "r", y: 0.5, to: [0.97, 0.3] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Or lay them out on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.4, to: [0.42, 0.32] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.62, to: [0.62, 0.5] }] },
  { file: "03-card", raw: "03-card", head: "Everything on the card.", notes: [{ text: "Pictures, labels<br>and checklists", side: "l", y: 0.6, to: [0.4, 0.62] }, { text: "A due date and<br>a priority", side: "r", y: 0.42, to: [0.6, 0.4] }] },
  { file: "04-material-you", raw: "04-material-you", head: "In your device's colours.", notes: [{ text: "Material You,<br>by default", side: "l", y: 0.42, to: [0.3, 0.3] }, { text: "From your<br>wallpaper", side: "r", y: 0.5, to: [0.62, 0.22] }] },
  { file: "05-theme", raw: "05-theme", head: "Or uwuBoard's own look.", notes: [{ text: "Seven brand<br>colours", side: "l", y: 0.66, to: [0.42, 0.74] }, { text: "Light, dark, or<br>by the clock", side: "r", y: 0.5, to: [0.58, 0.6] }] },
  { file: "06-sync", raw: "06-sync", head: "Sync without an account.", notes: [{ text: "Scan it with your<br>other device", side: "l", y: 0.6, to: [0.44, 0.62] }, { text: "Straight from one<br>to the other", side: "r", y: 0.42, to: [0.58, 0.4] }] },
  { file: "07-updates", raw: "07-updates", head: "Always up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.6, to: [0.4, 0.62] }, { text: "A note when a<br>new one's out", side: "r", y: 0.42, to: [0.66, 0.46] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around the first time.", notes: [{ text: "One step<br>at a time", side: "l", y: 0.6, to: [0.3, 0.5] }, { text: "Dark when<br>you like", side: "r", y: 0.4, to: [0.7, 0.15] }] },
];

const desktopScreens = [
  { file: "01-board", raw: "01-board", head: "Your to-dos, on a board.", notes: [{ text: "All your boards,<br>side by side", side: "l", y: 0.42, to: [0.08, 0.14] }, { text: "Drag cards from<br>To Do to Done", side: "r", y: 0.46, to: [0.62, 0.22] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Plan it on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.66, to: [0.36, 0.3] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.62, to: [0.62, 0.6] }] },
  { file: "03-command", raw: "03-command", head: "Search and do anything with Ctrl+K.", notes: [{ text: "Every board, card<br>and command", side: "l", y: 0.5, to: [0.32, 0.25] }, { text: "Or paste<br>a link", side: "r", y: 0.32, to: [0.66, 0.02] }] },
  { file: "04-card", raw: "04-card", head: "Details beside the board.", notes: [{ text: "Cards open in<br>a side panel", side: "l", y: 0.6, to: [0.6, 0.12] }, { text: "Pictures, labels<br>and checklists", side: "r", y: 0.5, to: [0.88, 0.58] }] },
  { file: "05-menu", raw: "05-menu", head: "Keep a board in sight.", notes: [{ text: "Pin it to your<br>desktop", side: "l", y: 0.4, to: [0.12, 0.51] }, { text: "Or follow its due<br>cards in the tray", side: "l", y: 0.74, to: [0.12, 0.55] }] },
  { file: "06-welcome", raw: "06-welcome", head: "Make it yours.", window: "Make uwuBoard yours", notes: [{ text: "Starts when you<br>sign in", side: "r", y: 0.32, to: [0.92, 0.22] }, { text: "Or your computer's<br>accent colour", side: "r", y: 0.66, to: [0.96, 0.53] }] },
  { file: "07-dark", raw: "07-dark", head: "Light, dark, or by the clock.", notes: [{ text: "Dark when<br>you like", side: "l", y: 0.42, to: [0.25, 0.3] }, { text: "In any brand<br>colour", side: "r", y: 0.5, to: [0.5, 0.02] }] },
  { file: "08-sync", raw: "08-sync", head: "Sync without an account.", notes: [{ text: "Scan it with your<br>phone", side: "l", y: 0.6, to: [0.47, 0.75] }, { text: "Straight from one<br>to the other", side: "r", y: 0.42, to: [0.6, 0.62] }] },
];

// The page's colours for each numbered picture, in order: a deep shade of a hue from the top-left
// (`from`) into a neighbouring one (`to`), hills in a third (`hill`), and the words and arrows in
// the app's own pastel brand colour of that hue (`ink`, theme.dart's colorThemes), which reads on it.
const themes = [
  { from: "#1f6b3d", to: "#13585a", hill: "#2f8a52", ink: "#ccffcc" }, // 01 green
  { from: "#0e6470", to: "#1c4f8a", hill: "#16808a", ink: "#ccffff" }, // 02 teal
  { from: "#3a3f9e", to: "#5b2f93", hill: "#4d55c4", ink: "#ccccff" }, // 03 indigo
  { from: "#7a2a84", to: "#9c2a5e", hill: "#9a3aa6", ink: "#ffccff" }, // 04 plum
  { from: "#a3294a", to: "#a8481f", hill: "#c23a5c", ink: "#ffcccc" }, // 05 raspberry
  { from: "#94560c", to: "#5e6a14", hill: "#b06c12", ink: "#ffffcc" }, // 06 amber
  { from: "#1d5c9e", to: "#1f6b3d", hill: "#2a74bf", ink: "#ccffff" }, // 07 blue
  { from: "#2b2f6e", to: "#4d2a6e", hill: "#3c418f", ink: "#ccccff" }, // 08 midnight, for the dark one
];
// The feature graphic sweeps through the first three.
const featureTheme = { from: "#1f6b3d", to: "#3a3f9e", via: "#0e6470", hill: "#2f8a52", hill2: "#4d55c4", ink: "#ccffcc" };

const css = `
@font-face { font-family: Jua; src: url("${juaFontUrl}"); }
* { box-sizing: border-box; margin: 0; }
body { width: var(--w); height: var(--h); overflow: hidden; background: linear-gradient(155deg, var(--from), var(--via, var(--from)) 45%, var(--to)); font-family: Jua, sans-serif; position: relative; }
.hill { position: absolute; border-radius: 50%; background: var(--hill); opacity: .55; }
.hill.dark { background: #000; opacity: .16; }
.head { position: absolute; left: 0; right: 0; text-align: center; color: var(--ink); line-height: 1.08; }
.screen { position: absolute; overflow: hidden; background: #fff; }
.screen img { width: 100%; height: 100%; object-fit: cover; object-position: top left; display: block; }
.frame { position: absolute; background: #121815; box-shadow: 0 40px 90px rgba(0,0,0,.35); }
.note { position: absolute; color: var(--ink); font-family: "Patrick Hand", "Segoe Print", cursive; text-align: center; line-height: 1.15; }
svg { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
.status { position: absolute; left: 0; right: 0; top: 0; display: flex; justify-content: space-between; align-items: center; font-family: Roboto, "Segoe UI", sans-serif; color: #121815; }
.titlebar { position: absolute; left: 0; right: 0; top: 0; display: flex; align-items: center; color: #eef2ef; font-family: "Segoe UI", sans-serif; background: #121815; }
`;

// Builds the HTML of one store picture of this size: the coloured page with `body` on it, and a
// script that draws each note's arrow once the fonts have loaded and everything is laid out.
function page({ width, height, body, theme }) {
  const cssVariables = Object.entries(theme).map(([name, value]) => {
    return `--${name}:${value}`;
  }).join(";");
  // Thinner arrows, with shorter heads, on the big landscape pictures.
  let strokeWidth;
  if (width > 2000) {
    strokeWidth = 5;
  } else {
    strokeWidth = 6;
  }
  let arrowHeadSize;
  if (width > 2000) {
    arrowHeadSize = 26;
  } else {
    arrowHeadSize = 34;
  }
  return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">
<style>:root{--w:${width}px;--h:${height}px;${cssVariables}}${css}</style></head><body>${body}
<svg id="arrows"></svg>
<script>
// Each note's arrow, from the note to the point on the screen it names, drawn once laid out.
document.fonts.ready.then(() => {
  const svg = document.getElementById('arrows');
  const ink = ${JSON.stringify(theme.ink)};
  const screen = document.querySelector('.screen').getBoundingClientRect();
  for (const note of document.querySelectorAll('.note')) {
    const noteBox = note.getBoundingClientRect();
    const [fractionX, fractionY] = JSON.parse(note.dataset.to);
    // The point the arrow ends on: a fraction of the way across and down the screen.
    const targetX = screen.left + fractionX * screen.width;
    const targetY = screen.top + fractionY * screen.height;
    const right = note.dataset.side === 'r';
    // The arrow starts from the middle of the note, just above it or just below it, whichever
    // side faces the point.
    let startX;
    if (right) {
      startX = noteBox.left + noteBox.width * 0.5;
    } else {
      startX = noteBox.left + noteBox.width * 0.5;
    }
    let startY;
    if (targetY < noteBox.top) {
      startY = noteBox.top - 14;
    } else {
      startY = noteBox.bottom + 14;
    }
    // A control point pushed sideways from the middle of the line, so the arrow curves outwards.
    let curveOffset;
    if (right) {
      curveOffset = 60;
    } else {
      curveOffset = -60;
    }
    const middleX = (startX + targetX) / 2 + curveOffset;
    const middleY = (startY + targetY) / 2;
    const curve = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    curve.setAttribute('d', 'M' + startX + ',' + startY + ' Q' + middleX + ',' + middleY + ' ' + targetX + ',' + targetY);
    curve.setAttribute('fill', 'none');
    curve.setAttribute('stroke', ink);
    curve.setAttribute('stroke-width', ${strokeWidth});
    curve.setAttribute('stroke-linecap', 'round');
    svg.appendChild(curve);
    // The arrow head: two short lines from the point, angled back either side of the curve's end.
    const angle = Math.atan2(targetY - middleY, targetX - middleX);
    const headLength = ${arrowHeadSize};
    for (const turn of [0.8, -0.8]) {
      const headLine = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      headLine.setAttribute('d', 'M' + targetX + ',' + targetY + ' L' + (targetX + Math.cos(angle + Math.PI * turn) * headLength) + ',' + (targetY + Math.sin(angle + Math.PI * turn) * headLength));
      headLine.setAttribute('stroke', ink);
      headLine.setAttribute('stroke-width', ${strokeWidth});
      headLine.setAttribute('stroke-linecap', 'round');
      svg.appendChild(headLine);
    }
  }
  document.body.dataset.ready = '1';
});
</script></body></html>`;
}

// The handwritten notes, each in the strip left or right of the device, at its height down the page.
// `zone` gives the middle of each strip and how wide a note may be.
const notesHtml = (notes, { height, fontSize, zone }) => {
  return notes.map((note) => {
    let centerX;
    if (note.side === "l") {
      centerX = zone.leftCenter;
    } else {
      centerX = zone.rightCenter;
    }
    return `<div class="note" data-side="${note.side}" data-to='${JSON.stringify(note.to)}' style="left:${centerX - zone.width / 2}px;width:${zone.width}px;top:${note.y * height}px;font-size:${fontSize}px">${note.text}</div>`;
  }).join("");
};

// A phone or a portrait tablet: headline above, the device in the middle, notes either side.
function portraitPage(description, pictureUrl, { tablet, theme }) {
  const width = 1620;
  const height = 2880;
  let screenWidth;
  if (tablet) {
    screenWidth = 920;
  } else {
    screenWidth = 800;
  }
  // A phone's status bar above the app, coloured from the picture's own top edge.
  let statusBarHeight;
  if (tablet) {
    statusBarHeight = 0;
  } else {
    statusBarHeight = 60;
  }
  // The screen keeps the shape the picture was taken at (600 × 1000 or 412 × 892).
  let heightPerWidth;
  if (tablet) {
    heightPerWidth = 1000 / 600;
  } else {
    heightPerWidth = 892 / 412;
  }
  const screenHeight = Math.round(screenWidth * heightPerWidth) + statusBarHeight;
  let bezel;
  if (tablet) {
    bezel = 44;
  } else {
    bezel = 30;
  }
  const left = (width - screenWidth) / 2;
  const top = 620;
  let status;
  if (tablet) {
    status = "";
  } else {
    status = `<div class="status" style="height:${statusBarHeight}px;padding:0 44px;font-size:30px;background:url('${pictureUrl}') top left / 100% 100000% no-repeat"><span>9:41</span><span>▴ ◼</span></div>`;
  }
  let frameRadius;
  if (tablet) {
    frameRadius = 70;
  } else {
    frameRadius = 110;
  }
  let screenRadius;
  if (tablet) {
    screenRadius = 30;
  } else {
    screenRadius = 80;
  }
  let noteFontSize;
  if (tablet) {
    noteFontSize = 52;
  } else {
    noteFontSize = 60;
  }
  const body = `
<div class="hill" style="width:2600px;height:1400px;left:-1300px;top:1300px"></div>
<div class="hill dark" style="width:1800px;height:1600px;left:900px;top:1800px"></div>
<div class="head" style="top:150px;font-size:150px">${description.head}</div>
<div class="frame" style="left:${left - bezel}px;top:${top - bezel}px;width:${screenWidth + 2 * bezel}px;height:${screenHeight + 2 * bezel}px;border-radius:${frameRadius}px"></div>
<div class="screen" style="left:${left}px;top:${top}px;width:${screenWidth}px;height:${screenHeight}px;border-radius:${screenRadius}px"><img src="${pictureUrl}" style="position:absolute;top:${statusBarHeight}px;height:${screenHeight - statusBarHeight}px">${status}</div>
${notesHtml(description.notes, { width, height, fontSize: noteFontSize, zone: { leftCenter: left / 2, rightCenter: width - left / 2, width: left - 36 } })}`;
  return { width, height, html: page({ width, height, body, theme }) };
}

// A landscape tablet or the desktop: headline above, the device or window, notes either side.
function landscapePage(description, pictureUrl, { desktop: isDesktop, theme }) {
  const width = 2880;
  const height = 1620;
  const welcome = Boolean(description.window);
  // The screen keeps the shape the picture was taken at.
  let heightPerWidth;
  if (welcome) {
    heightPerWidth = 660 / 940;
  } else if (isDesktop) {
    heightPerWidth = 900 / 1440;
  } else {
    heightPerWidth = 800 / 1280;
  }
  let screenWidth;
  if (welcome) {
    screenWidth = 1620;
  } else {
    screenWidth = 2000;
  }
  const screenHeight = Math.round(screenWidth * heightPerWidth);
  const left = (width - screenWidth) / 2;
  let top;
  if (welcome) {
    top = 330;
  } else {
    top = 300;
  }
  let frame;
  if (isDesktop) {
    // A window: its own title bar is the app's (or, for Make it yours, the system's simple one).
    frame = `<div class="frame" style="left:${left - 3}px;top:${top - 3}px;width:${screenWidth + 6}px;height:${screenHeight + 6}px;border-radius:18px;background:#0b0f0c"></div>`;
  } else {
    frame = `<div class="frame" style="left:${left - 40}px;top:${top - 40}px;width:${screenWidth + 80}px;height:${screenHeight + 80}px;border-radius:60px"></div>`;
  }
  let screenRadius;
  if (isDesktop) {
    screenRadius = 14;
  } else {
    screenRadius = 24;
  }
  const body = `
<div class="hill" style="width:2400px;height:1300px;left:-1100px;top:900px"></div>
<div class="hill dark" style="width:2200px;height:1500px;left:1900px;top:1000px"></div>
<div class="head" style="top:70px;font-size:130px">${description.head}</div>
${frame}
<div class="screen" style="left:${left}px;top:${top}px;width:${screenWidth}px;height:${screenHeight}px;border-radius:${screenRadius}px"><img src="${pictureUrl}"></div>
${notesHtml(description.notes, { width, height, fontSize: 54, zone: { leftCenter: left / 2, rightCenter: width - left / 2, width: left - 40 } })}`;
  return { width, height, html: page({ width, height, body, theme }) };
}

// The Play Store's feature graphic: the icon, the name and a line about the app, beside a tilted phone.
function featureGraphic() {
  const width = 1024;
  const height = 500;
  const body = `
<div class="hill" style="width:900px;height:700px;left:-300px;top:260px"></div>
<div class="hill" style="width:800px;height:800px;left:620px;top:200px;background:var(--hill2)"></div>
<img src="${iconUrl}" style="position:absolute;left:70px;top:120px;width:150px;height:150px;border-radius:34px;box-shadow:0 18px 40px rgba(0,0,0,.3)">
<div style="position:absolute;left:250px;top:118px;color:var(--ink);font-size:88px">uwuBoard</div>
<div style="position:absolute;left:256px;top:232px;color:#eaffea;font-size:38px">The Kanban way</div>
<div style="position:absolute;left:72px;top:330px;width:440px;color:var(--ink);font-family:'Patrick Hand',cursive;font-size:34px;line-height:1.15">Boards, Timelines and cards, on your phone and your computer</div>
<div class="frame" style="left:676px;top:58px;width:300px;height:620px;border-radius:44px;transform:rotate(8deg)"></div>
<div class="screen" style="left:690px;top:72px;width:272px;height:590px;border-radius:34px;transform:rotate(8deg)"><img src="${rawPictureUrl("phone-04-material-you")}"></div>`;
  return { width, height, html: page({ width, height, body, theme: featureTheme }).replace('<svg id="arrows"></svg>', "").replace("<div class=\"screen\"", "<div class=\"screen\"") };
}

// Opens the page in a browser window of its exact size, waits for the arrows, and saves a PNG.
async function render(browser, { width, height, html }, outputPath) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  const tab = await context.newPage();
  // From a file, so the page may read the pictures and fonts beside it.
  const pageFile = join(thisFolder, ".page.html");
  writeFileSync(pageFile, html);
  await tab.goto(pathToFileURL(pageFile).href, { waitUntil: "networkidle" });
  await tab.waitForFunction(() => {
    return document.body.dataset.ready === "1" || !document.querySelector(".note");
  }, null, { timeout: 15000 }).catch(() => {});
  await tab.waitForTimeout(300);
  mkdirSync(dirname(outputPath), { recursive: true });
  await tab.screenshot({ path: outputPath, type: "png" });
  await context.close();
  console.log(outputPath.replace(docsFolder, "docs"));
}

// Each numbered picture for the phone, both tablets and the desktop, then the feature graphic.
const browser = await chromium.launch();
try {
  for (const [index, description] of portraitScreens.entries()) {
    const theme = themes[index];
    await render(browser, portraitPage(description, rawPictureUrl(`phone-${description.raw}`), { tablet: false, theme }), join(docsFolder, "phone-assets", `${description.file}.png`));
    await render(browser, portraitPage(description, rawPictureUrl(`tablet7-${description.raw}`), { tablet: true, theme }), join(docsFolder, "tablet-assets/7-inch", `${description.file}.png`));
    const landscapeDescription = landscapeScreens[index];
    await render(browser, landscapePage(landscapeDescription, rawPictureUrl(`tablet10-${landscapeDescription.raw}`), { desktop: false, theme }), join(docsFolder, "tablet-assets/10-inch", `${landscapeDescription.file}.png`));
  }
  for (const [index, description] of desktopScreens.entries()) {
    await render(browser, landscapePage(description, rawPictureUrl(`desktop-${description.raw}`), { desktop: true, theme: themes[index] }), join(docsFolder, "desktop-assets", `${description.file}.png`));
  }
  await render(browser, featureGraphic(), join(docsFolder, "feature-graphic.png"));
} finally {
  await browser.close();
}
