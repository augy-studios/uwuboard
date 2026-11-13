// Frames the pictures from capture.mjs as store screenshots, in the style SG Bus Timings' have:
// a dark green page, a headline in Jua, the app in a phone, tablet or window, and handwritten
// notes with arrows to what they're about. Writes them into docs/:
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

const here = dirname(fileURLToPath(import.meta.url));
const raw = (f) => pathToFileURL(join(here, "raw", `${f}.png`)).href;
const docs = join(here, "../../../docs");
const jua = pathToFileURL(join(here, "../../assets/fonts/Jua-Regular.ttf")).href;
const icon = pathToFileURL(join(here, "../../assets/images/icon-512.png")).href;

// What each picture says. `to` is where an arrow points, as a fraction of the screen it's on.
const portrait = [
  { file: "01-board", raw: "01-board", head: "Your to-dos,<br>on a board.", notes: [{ text: "Drag cards from<br>To Do to Done", side: "l", y: 0.42, to: [0.3, 0.22] }, { text: "Every action in<br>the edge tray", side: "r", y: 0.62, to: [0.9, 0.2] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Or lay them out<br>on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.62, to: [0.62, 0.27] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.78, to: [0.82, 0.36] }] },
  { file: "03-card", raw: "03-card", head: "Everything<br>on the card.", notes: [{ text: "Pictures, labels<br>and checklists", side: "l", y: 0.66, to: [0.18, 0.62] }, { text: "A due date and<br>a priority", side: "r", y: 0.42, to: [0.82, 0.38] }] },
  { file: "04-material-you", raw: "04-material-you", head: "In your phone's<br>colours.", notes: [{ text: "Material You,<br>by default", side: "l", y: 0.4, to: [0.3, 0.22] }, { text: "From your<br>wallpaper", side: "r", y: 0.6, to: [0.6, 0.3] }] },
  { file: "05-theme", raw: "05-theme", head: "Or uwuBoard's<br>own look.", notes: [{ text: "Seven brand<br>colours", side: "l", y: 0.7, to: [0.35, 0.96] }, { text: "Light, dark, or<br>by the clock", side: "r", y: 0.6, to: [0.7, 0.9] }] },
  { file: "06-sync", raw: "06-sync", head: "Sync without<br>an account.", notes: [{ text: "Scan it with your<br>other device", side: "l", y: 0.66, to: [0.38, 0.84] }, { text: "Straight from one<br>to the other", side: "r", y: 0.46, to: [0.62, 0.77] }] },
  { file: "07-updates", raw: "07-updates", head: "Always<br>up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.66, to: [0.3, 0.83] }, { text: "A note when a<br>new one's out", side: "r", y: 0.48, to: [0.88, 0.71] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around<br>the first time.", notes: [{ text: "One step<br>at a time", side: "l", y: 0.5, to: [0.4, 0.78] }, { text: "Dark when<br>you like", side: "r", y: 0.34, to: [0.62, 0.1] }] },
];

const landscape = [
  { file: "01-board", raw: "01-board", head: "Your to-dos, on a board.", notes: [{ text: "Drag cards from<br>To Do to Done", side: "l", y: 0.42, to: [0.32, 0.28] }, { text: "Every action in<br>the edge tray", side: "r", y: 0.5, to: [0.97, 0.3] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Or lay them out on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.4, to: [0.42, 0.32] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.62, to: [0.62, 0.5] }] },
  { file: "03-card", raw: "03-card", head: "Everything on the card.", notes: [{ text: "Pictures, labels<br>and checklists", side: "l", y: 0.6, to: [0.4, 0.62] }, { text: "A due date and<br>a priority", side: "r", y: 0.42, to: [0.6, 0.4] }] },
  { file: "04-material-you", raw: "04-material-you", head: "In your device's colours.", notes: [{ text: "Material You,<br>by default", side: "l", y: 0.42, to: [0.3, 0.3] }, { text: "From your<br>wallpaper", side: "r", y: 0.5, to: [0.62, 0.22] }] },
  { file: "05-theme", raw: "05-theme", head: "Or uwuBoard's own look.", notes: [{ text: "Seven brand<br>colours", side: "l", y: 0.66, to: [0.42, 0.74] }, { text: "Light, dark, or<br>by the clock", side: "r", y: 0.5, to: [0.58, 0.6] }] },
  { file: "06-sync", raw: "06-sync", head: "Sync without an account.", notes: [{ text: "Scan it with your<br>other device", side: "l", y: 0.6, to: [0.44, 0.62] }, { text: "Straight from one<br>to the other", side: "r", y: 0.42, to: [0.58, 0.4] }] },
  { file: "07-updates", raw: "07-updates", head: "Always up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.6, to: [0.4, 0.62] }, { text: "A note when a<br>new one's out", side: "r", y: 0.42, to: [0.66, 0.46] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around the first time.", notes: [{ text: "One step<br>at a time", side: "l", y: 0.6, to: [0.3, 0.5] }, { text: "Dark when<br>you like", side: "r", y: 0.4, to: [0.7, 0.15] }] },
];

const desktop = [
  { file: "01-board", raw: "01-board", head: "Your to-dos, on a board.", notes: [{ text: "All your boards,<br>side by side", side: "l", y: 0.42, to: [0.08, 0.14] }, { text: "Drag cards from<br>To Do to Done", side: "r", y: 0.46, to: [0.62, 0.22] }] },
  { file: "02-timeline", raw: "02-timeline", head: "Plan it on a Timeline.", notes: [{ text: "Each task, a bar<br>across its dates", side: "l", y: 0.66, to: [0.36, 0.3] }, { text: "Red arrows when<br>dates clash", side: "r", y: 0.62, to: [0.62, 0.6] }] },
  { file: "03-command", raw: "03-command", head: "Search and do anything with Ctrl+K.", notes: [{ text: "Every board, card<br>and command", side: "l", y: 0.5, to: [0.32, 0.25] }, { text: "Or paste<br>a link", side: "r", y: 0.32, to: [0.66, 0.02] }] },
  { file: "04-card", raw: "04-card", head: "Details beside the board.", notes: [{ text: "Cards open in<br>a side panel", side: "l", y: 0.6, to: [0.6, 0.12] }, { text: "Pictures, labels<br>and checklists", side: "r", y: 0.5, to: [0.88, 0.58] }] },
  { file: "05-menu", raw: "05-menu", head: "Keep a board in sight.", notes: [{ text: "Pin it to your<br>desktop", side: "l", y: 0.4, to: [0.12, 0.51] }, { text: "Or follow its due<br>cards in the tray", side: "l", y: 0.74, to: [0.12, 0.55] }] },
  { file: "06-welcome", raw: "06-welcome", head: "Make it yours.", window: "Make uwuBoard yours", notes: [{ text: "Starts when you<br>sign in", side: "r", y: 0.32, to: [0.92, 0.22] }, { text: "Or your computer's<br>accent colour", side: "r", y: 0.66, to: [0.96, 0.53] }] },
  { file: "07-dark", raw: "07-dark", head: "Light, dark, or by the clock.", notes: [{ text: "Dark when<br>you like", side: "l", y: 0.42, to: [0.25, 0.3] }, { text: "In any brand<br>colour", side: "r", y: 0.5, to: [0.5, 0.02] }] },
  { file: "08-sync", raw: "08-sync", head: "Sync without an account.", notes: [{ text: "Scan it with your<br>phone", side: "l", y: 0.6, to: [0.47, 0.75] }, { text: "Straight from one<br>to the other", side: "r", y: 0.42, to: [0.6, 0.62] }] },
];

const css = `
@font-face { font-family: Jua; src: url("${jua}"); }
* { box-sizing: border-box; margin: 0; }
body { width: var(--w); height: var(--h); overflow: hidden; background: #1f6b3d; font-family: Jua, sans-serif; position: relative; }
.hill { position: absolute; border-radius: 50%; background: #1b5e36; }
.head { position: absolute; left: 0; right: 0; text-align: center; color: #ccffcc; line-height: 1.08; }
.screen { position: absolute; overflow: hidden; background: #fff; }
.screen img { width: 100%; height: 100%; object-fit: cover; object-position: top left; display: block; }
.frame { position: absolute; background: #121815; box-shadow: 0 40px 90px rgba(0,0,0,.35); }
.note { position: absolute; color: #ccffcc; font-family: "Patrick Hand", "Segoe Print", cursive; text-align: center; line-height: 1.15; }
svg { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
.status { position: absolute; left: 0; right: 0; top: 0; display: flex; justify-content: space-between; align-items: center; font-family: Roboto, "Segoe UI", sans-serif; color: #121815; }
.titlebar { position: absolute; left: 0; right: 0; top: 0; display: flex; align-items: center; color: #eef2ef; font-family: "Segoe UI", sans-serif; background: #121815; }
`;

function page({ w, h, body }) {
  return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">
<style>:root{--w:${w}px;--h:${h}px}${css}</style></head><body>${body}
<svg id="arrows"></svg>
<script>
// Each note's arrow, from the note to the point on the screen it names, drawn once laid out.
document.fonts.ready.then(() => {
  const svg = document.getElementById('arrows');
  const screen = document.querySelector('.screen').getBoundingClientRect();
  for (const n of document.querySelectorAll('.note')) {
    const r = n.getBoundingClientRect();
    const [fx, fy] = JSON.parse(n.dataset.to);
    const tx = screen.left + fx * screen.width, ty = screen.top + fy * screen.height;
    const right = n.dataset.side === 'r';
    const sx = right ? r.left + r.width * 0.5 : r.left + r.width * 0.5;
    const sy = ty < r.top ? r.top - 14 : r.bottom + 14;
    const mx = (sx + tx) / 2 + (right ? 60 : -60), my = (sy + ty) / 2;
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', 'M' + sx + ',' + sy + ' Q' + mx + ',' + my + ' ' + tx + ',' + ty);
    p.setAttribute('fill', 'none'); p.setAttribute('stroke', '#ccffcc'); p.setAttribute('stroke-width', ${w > 2000 ? 5 : 6}); p.setAttribute('stroke-linecap', 'round');
    svg.appendChild(p);
    const a = Math.atan2(ty - my, tx - mx), L = ${w > 2000 ? 26 : 34};
    for (const d of [0.8, -0.8]) {
      const h = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      h.setAttribute('d', 'M' + tx + ',' + ty + ' L' + (tx + Math.cos(a + Math.PI * d) * L) + ',' + (ty + Math.sin(a + Math.PI * d) * L));
      h.setAttribute('stroke', '#ccffcc'); h.setAttribute('stroke-width', ${w > 2000 ? 5 : 6}); h.setAttribute('stroke-linecap', 'round');
      svg.appendChild(h);
    }
  }
  document.body.dataset.ready = '1';
});
</script></body></html>`;
}

const notesHtml = (notes, { w, h, fs, zone }) =>
  notes.map((n) => {
    const x = n.side === "l" ? zone.l : zone.r;
    return `<div class="note" data-side="${n.side}" data-to='${JSON.stringify(n.to)}' style="left:${x - zone.w / 2}px;width:${zone.w}px;top:${n.y * h}px;font-size:${fs}px">${n.text}</div>`;
  }).join("");

// A phone or a portrait tablet: headline above, the device in the middle, notes either side.
function portraitPage(s, raw, { tablet }) {
  const w = 1620, h = 2880;
  const sw = tablet ? 920 : 800;
  // A phone's status bar above the app, coloured from the picture's own top edge.
  const bar = tablet ? 0 : 60;
  const sh = Math.round(sw * (tablet ? 1000 / 600 : 892 / 412)) + bar;
  const bezel = tablet ? 44 : 30;
  const left = (w - sw) / 2, top = 620;
  const status = tablet ? "" : `<div class="status" style="height:${bar}px;padding:0 44px;font-size:30px;background:url('${raw}') top left / 100% 100000% no-repeat"><span>9:41</span><span>▴ ◼</span></div>`;
  const body = `
<div class="hill" style="width:2600px;height:1400px;left:-1300px;top:1300px"></div>
<div class="hill" style="width:1800px;height:1600px;left:900px;top:1800px"></div>
<div class="head" style="top:150px;font-size:150px">${s.head}</div>
<div class="frame" style="left:${left - bezel}px;top:${top - bezel}px;width:${sw + 2 * bezel}px;height:${sh + 2 * bezel}px;border-radius:${tablet ? 70 : 110}px"></div>
<div class="screen" style="left:${left}px;top:${top}px;width:${sw}px;height:${sh}px;border-radius:${tablet ? 30 : 80}px"><img src="${raw}" style="position:absolute;top:${bar}px;height:${sh - bar}px">${status}</div>
${notesHtml(s.notes, { w, h, fs: tablet ? 52 : 60, zone: { l: left / 2, r: w - left / 2, w: left - 36 } })}`;
  return { w, h, html: page({ w, h, body }) };
}

// A landscape tablet or the desktop: headline above, the device or window, notes either side.
function landscapePage(s, raw, { desktop: isDesktop }) {
  const w = 2880, h = 1620;
  const welcome = !!s.window;
  const ratio = welcome ? 660 / 940 : isDesktop ? 900 / 1440 : 800 / 1280;
  const sw = welcome ? 1620 : 2000, sh = Math.round(sw * ratio);
  const left = (w - sw) / 2, top = welcome ? 330 : 300;
  let frame;
  if (isDesktop) {
    // A window: its own title bar is the app's (or, for Make it yours, the system's simple one).
    frame = `<div class="frame" style="left:${left - 3}px;top:${top - 3}px;width:${sw + 6}px;height:${sh + 6}px;border-radius:18px;background:#0b0f0c"></div>`;
  } else {
    frame = `<div class="frame" style="left:${left - 40}px;top:${top - 40}px;width:${sw + 80}px;height:${sh + 80}px;border-radius:60px"></div>`;
  }
  const body = `
<div class="hill" style="width:2400px;height:1300px;left:-1100px;top:900px"></div>
<div class="hill" style="width:2200px;height:1500px;left:1900px;top:1000px"></div>
<div class="head" style="top:70px;font-size:130px">${s.head}</div>
${frame}
<div class="screen" style="left:${left}px;top:${top}px;width:${sw}px;height:${sh}px;border-radius:${isDesktop ? 14 : 24}px"><img src="${raw}"></div>
${notesHtml(s.notes, { w, h, fs: 54, zone: { l: left / 2, r: w - left / 2, w: left - 40 } })}`;
  return { w, h, html: page({ w, h, body }) };
}

function featureGraphic() {
  const w = 1024, h = 500;
  const body = `
<div class="hill" style="width:900px;height:700px;left:-300px;top:260px"></div>
<div class="hill" style="width:800px;height:800px;left:620px;top:200px"></div>
<img src="${icon}" style="position:absolute;left:70px;top:120px;width:150px;height:150px;border-radius:34px;box-shadow:0 18px 40px rgba(0,0,0,.3)">
<div style="position:absolute;left:250px;top:118px;color:#ccffcc;font-size:88px">uwuBoard</div>
<div style="position:absolute;left:256px;top:232px;color:#eaffea;font-size:38px">The Kanban way</div>
<div style="position:absolute;left:72px;top:330px;width:440px;color:#ccffcc;font-family:'Patrick Hand',cursive;font-size:34px;line-height:1.15">Boards, Timelines and cards, on your phone and your computer</div>
<div class="frame" style="left:676px;top:58px;width:300px;height:620px;border-radius:44px;transform:rotate(8deg)"></div>
<div class="screen" style="left:690px;top:72px;width:272px;height:590px;border-radius:34px;transform:rotate(8deg)"><img src="${raw("phone-04-material-you")}"></div>`;
  return { w, h, html: page({ w, h, body }).replace('<svg id="arrows"></svg>', "").replace("<div class=\"screen\"", "<div class=\"screen\"") };
}

async function render(browser, { w, h, html }, out) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  // From a file, so the page may read the pictures and fonts beside it.
  const tmp = join(here, ".page.html");
  writeFileSync(tmp, html);
  await p.goto(pathToFileURL(tmp).href, { waitUntil: "networkidle" });
  await p.waitForFunction(() => document.body.dataset.ready === "1" || !document.querySelector(".note"), null, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(300);
  mkdirSync(dirname(out), { recursive: true });
  await p.screenshot({ path: out, type: "png" });
  await ctx.close();
  console.log(out.replace(docs, "docs"));
}

const browser = await chromium.launch();
try {
  for (const [i, s] of portrait.entries()) {
    await render(browser, portraitPage(s, raw(`phone-${s.raw}`), { tablet: false }), join(docs, "phone-assets", `${s.file}.png`));
    await render(browser, portraitPage(s, raw(`tablet7-${s.raw}`), { tablet: true }), join(docs, "tablet-assets/7-inch", `${s.file}.png`));
    const l = landscape[i];
    await render(browser, landscapePage(l, raw(`tablet10-${l.raw}`), { desktop: false }), join(docs, "tablet-assets/10-inch", `${l.file}.png`));
  }
  for (const s of desktop) await render(browser, landscapePage(s, raw(`desktop-${s.raw}`), { desktop: true }), join(docs, "desktop-assets", `${s.file}.png`));
  await render(browser, featureGraphic(), join(docs, "feature-graphic.png"));
} finally {
  await browser.close();
}
