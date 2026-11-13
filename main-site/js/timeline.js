'use strict';

/* The Timeline view of a board: a Gantt chart, as Jira's Timeline draws one. The board's
   columns are its phases and their cards its tasks, so a board can switch between Kanban
   and Timeline at any time without changing what's in it.

   Each task is a bar from its start date to its due date (one day when it has only one of
   them), filled as far as its checklist is done. A milestone is a diamond on its day. Drag a
   bar to move it, or either end to change its length. Arrows run from the tasks a task waits
   for (`dependsOn`) to it, red when the dates clash: the one waited for ends on or after the
   day the other starts. Nothing moves on its own; the red says to look. A line marks today,
   and the scale zooms between weeks, months and quarters.

   Dates are kept as YYYY-MM-DD and worked in whole days (UTC day numbers), so a clock change
   never moves a bar. Uses script.js's state and helpers (S, esc, touch, persistBoard, ...),
   so nothing here runs until script.js calls Timeline.render(). */
(function () {
  const ZOOM_KEY = 'uwuboard.timeline.zoom';
  const ZOOMS = {
    weeks: { label: 'Weeks', ppd: 40, margin: 7, newLength: 3 },
    months: { label: 'Months', ppd: 14, margin: 21, newLength: 7 },
    quarters: { label: 'Quarters', ppd: 4, margin: 45, newLength: 14 },
  };
  const ROW = { phase: 38, task: 40, add: 34 };
  const HEAD = 52;
  // The colour of a task with no label of its own, by phase: Jira's blue, amber, green, then more.
  const PHASE_COLOURS = ['#4c9aff', '#ffb31f', '#36b37e', '#ff7452', '#998dd9', '#00b8d9'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DOW = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  /* ---- dates as day numbers ---- */

  const DAY = 86400000;
  const isIso = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
  const dayOf = (iso) => { const [y, m, d] = iso.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / DAY); };
  const isoOf = (n) => new Date(n * DAY).toISOString().slice(0, 10);
  const dateOf = (n) => new Date(n * DAY);
  function todayIso() {
    const t = new Date();
    return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
  }

  // A task's span as day numbers, or null without dates. One date alone is a one-day task;
  // a milestone is always one day, on its due date.
  function span(card) {
    const s = isIso(card.start) ? dayOf(card.start) : null;
    const d = isIso(card.due) ? dayOf(card.due) : null;
    if (s === null && d === null) return null;
    if (card.milestone) { const day = d ?? s; return { start: day, end: day }; }
    const start = s ?? d;
    const end = d ?? s;
    return start <= end ? { start, end } : { start: end, end: start };
  }

  function progress(card) {
    const list = card.checklist || [];
    return list.length ? list.filter((c) => c.done).length / list.length : 0;
  }

  /* ---- zoom ---- */

  function getZoom() {
    try { const z = localStorage.getItem(ZOOM_KEY); if (ZOOMS[z]) return z; } catch { /* the default */ }
    return 'months';
  }
  function setZoom(z) {
    try { localStorage.setItem(ZOOM_KEY, z); } catch { /* this visit only */ }
  }

  /* ---- layout ---- */

  // The rows top to bottom: each phase, its tasks, and a row to add one; then one to add a phase.
  function rowsOf(board) {
    const rows = [];
    let y = 0;
    board.columns.forEach((col, i) => {
      rows.push({ kind: 'phase', col, colour: PHASE_COLOURS[i % PHASE_COLOURS.length], y, h: ROW.phase });
      y += ROW.phase;
      for (const card of col.cards) {
        rows.push({ kind: 'task', col, card, colour: card.labels?.[0]?.color || PHASE_COLOURS[i % PHASE_COLOURS.length], y, h: ROW.task });
        y += ROW.task;
      }
      rows.push({ kind: 'add', col, y, h: ROW.add });
      y += ROW.add;
    });
    rows.push({ kind: 'addPhase', y, h: ROW.add });
    y += ROW.add;
    return { rows, height: y };
  }

  // The days on show: every task and today, with a margin, from the start of a week (Monday)
  // or month, and wide enough to fill the space there is.
  function rangeOf(board, zoom, minWidth) {
    const z = ZOOMS[zoom];
    const today = dayOf(todayIso());
    let lo = today, hi = today;
    for (const col of board.columns) {
      for (const card of col.cards) {
        const s = span(card);
        if (s) { lo = Math.min(lo, s.start); hi = Math.max(hi, s.end); }
      }
    }
    lo -= z.margin;
    hi += z.margin;
    const d = dateOf(lo);
    if (zoom === 'weeks') lo -= (d.getUTCDay() + 6) % 7;
    else lo = Math.round(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) / DAY);
    const days = Math.max(hi - lo + 1, Math.ceil(minWidth / z.ppd));
    return { lo, days, today };
  }

  /* ---- drawing ---- */

  // The two rows of the header and the gridlines under them.
  function scale(range, zoom) {
    const { ppd } = ZOOMS[zoom];
    const top = [];
    const bottom = [];
    const lines = [];
    let lastTop = null;
    for (let n = range.lo; n < range.lo + range.days; n++) {
      const d = dateOf(n);
      const x = (n - range.lo) * ppd;
      const m = d.getUTCMonth(), y = d.getUTCFullYear(), day = d.getUTCDate();
      const topKey = zoom === 'quarters' ? `${y}Q${Math.floor(m / 3)}` : `${y}-${m}`;
      if (topKey !== lastTop) {
        top.push({ x, text: zoom === 'quarters' ? `Q${Math.floor(m / 3) + 1} ${y}` : `${MONTHS[m]} ${y}` });
        lastTop = topKey;
      }
      if (zoom === 'weeks') {
        bottom.push({ x, w: ppd, text: `${DOW[d.getUTCDay()]} ${day}`, weekend: d.getUTCDay() % 6 === 0 });
        lines.push({ x, strong: d.getUTCDay() === 1 });
      } else if (zoom === 'months' && d.getUTCDay() === 1) {
        bottom.push({ x, w: 7 * ppd, text: `${day}` });
        lines.push({ x, strong: day <= 7 });
      } else if (zoom === 'quarters' && day === 1) {
        bottom.push({ x, w: 30 * ppd, text: MONTHS[m] });
        lines.push({ x, strong: m % 3 === 0 });
      }
    }
    return { top, bottom, lines };
  }

  const fmt = (n) => { const d = dateOf(n); return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`; };

  // The board on show, and the width it was drawn for: a chart drawn before it had any room
  // (the app still hidden as a board opens), or for a different width, is drawn again.
  let current = null;
  let drawnWidth = 0;
  let sizer = null;

  function watchSize(root) {
    if (sizer) return;
    sizer = new ResizeObserver(() => {
      const w = root.clientWidth;
      if (!current || root.classList.contains('hidden') || !w || w === drawnWidth) return;
      if (current !== getActiveBoard?.()) return;
      render(current);
    });
    sizer.observe(root);
  }

  function render(board) {
    const root = document.getElementById('timeline-container');
    watchSize(root);
    const old = root.querySelector('.tl-scroll');
    // Where it was scrolled to, kept across a redraw; not from a chart drawn with no room,
    // which never scrolled anywhere.
    const keep = old && drawnWidth ? { left: old.scrollLeft, top: old.scrollTop } : null;
    current = board;
    drawnWidth = root.clientWidth;
    const zoom = getZoom();
    const { ppd } = ZOOMS[zoom];
    const listW = window.innerWidth <= 720 ? 132 : 240;
    const minWidth = Math.max(root.clientWidth - listW, 320);
    const range = rangeOf(board, zoom, minWidth);
    const chartW = range.days * ppd;
    const { rows, height } = rowsOf(board);
    const sc = scale(range, zoom);
    const xOf = (n) => (n - range.lo) * ppd;
    const todayX = xOf(range.today) + ppd / 2;

    const listRows = rows.map((r) => {
      const style = `top:${r.y}px;height:${r.h}px`;
      if (r.kind === 'phase') {
        return `<button type="button" class="tl-phase" style="${style}" data-phase="${esc(r.col.id)}" title="Rename or delete this phase">` +
          `<span class="tl-swatch" style="background:${r.colour}"></span><span class="tl-name">${esc(r.col.name)}</span>` +
          `<span class="tl-count">${r.col.cards.length}</span></button>`;
      }
      if (r.kind === 'task') {
        const s = span(r.card);
        const when = s ? (s.start === s.end ? fmt(s.start) : `${fmt(s.start)} – ${fmt(s.end)}`) : 'No dates';
        return `<button type="button" class="tl-task${s ? '' : ' undated'}" style="${style}" data-card="${esc(r.card.id)}" data-col="${esc(r.col.id)}">` +
          `<span class="tl-name">${r.card.milestone ? '<span class="tl-diamond-sm" aria-hidden="true"></span>' : ''}${esc(r.card.title)}</span>` +
          `<span class="tl-when">${when}</span></button>`;
      }
      if (r.kind === 'add') return `<button type="button" class="tl-add" style="${style}" data-add="${esc(r.col.id)}">+ Add task</button>`;
      return `<button type="button" class="tl-add tl-add-phase" style="${style}" data-add-phase>+ Add phase</button>`;
    }).join('');

    // Row stripes, bars, milestones and phase roll-ups.
    const bars = new Map(); // card id -> { x1, x2, y }
    const chartRows = rows.map((r) => {
      if (r.kind === 'phase') {
        const spans = r.col.cards.map(span).filter(Boolean);
        if (!spans.length) return `<div class="tl-row tl-row-phase" style="top:${r.y}px;height:${r.h}px"></div>`;
        const a = Math.min(...spans.map((s) => s.start)), b = Math.max(...spans.map((s) => s.end));
        return `<div class="tl-row tl-row-phase" style="top:${r.y}px;height:${r.h}px">` +
          `<span class="tl-rollup" style="left:${xOf(a)}px;width:${(b - a + 1) * ppd}px;background:${r.colour}" title="${esc(r.col.name)}: ${fmt(a)} – ${fmt(b)}"></span></div>`;
      }
      if (r.kind !== 'task') return '';
      const s = span(r.card);
      const id = esc(r.card.id);
      if (!s) {
        return `<div class="tl-row tl-row-task undated" style="top:${r.y}px;height:${r.h}px" data-card="${id}" data-col="${esc(r.col.id)}" title="Press a day to give “${esc(r.card.title)}” dates"></div>`;
      }
      const x1 = xOf(s.start), x2 = xOf(s.end) + ppd, cy = r.y + r.h / 2;
      bars.set(r.card.id, { x1, x2, y: cy });
      const late = !r.card.milestone && isIso(r.card.due) && r.card.due < todayIso() && progress(r.card) < 1;
      if (r.card.milestone) {
        return `<div class="tl-row tl-row-task" style="top:${r.y}px;height:${r.h}px">` +
          `<div class="tl-milestone" style="left:${x1 + ppd / 2 - 11}px" data-card="${id}" data-col="${esc(r.col.id)}" tabindex="0" role="button" aria-label="${esc(r.card.title)}, milestone, ${fmt(s.start)}">` +
          `<span class="tl-diamond" style="background:${r.colour}"></span><span class="tl-label">${esc(r.card.title)}</span></div></div>`;
      }
      // The title just past the bar's end, where it reads whatever the bar's colour.
      // A late task says so in words, not only with its red edge (WCAG 1.4.1).
      const label = `<span class="tl-label${late ? ' late' : ''}" style="left:${x2 + 8}px">${esc(r.card.title)}${late ? ' (late)' : ''}</span>`;
      const pct = Math.round(progress(r.card) * 100);
      return `<div class="tl-row tl-row-task" style="top:${r.y}px;height:${r.h}px">` +
        `<div class="tl-bar${late ? ' late' : ''}" style="left:${x1}px;width:${x2 - x1}px;--bar:${r.colour}" data-card="${id}" data-col="${esc(r.col.id)}" tabindex="0" role="button" ` +
        `aria-label="${esc(r.card.title)}, ${fmt(s.start)} to ${fmt(s.end)}${(r.card.checklist || []).length ? `, ${pct}% done` : ''}">` +
        `<span class="tl-fill" style="width:${pct}%"></span><span class="tl-h tl-h-start" aria-hidden="true"></span><span class="tl-h tl-h-end" aria-hidden="true"></span></div>` +
        label + '</div>';
    }).join('');

    // Dependency arrows, from the end of the task waited for to the start of the one waiting.
    const arrows = [];
    for (const r of rows) {
      if (r.kind !== 'task' || !bars.has(r.card.id)) continue;
      for (const depId of r.card.dependsOn || []) {
        const from = bars.get(depId);
        if (!from) continue;
        const to = bars.get(r.card.id);
        const pred = findCard(board, depId);
        const clash = clashes(pred, r.card);
        const midY = to.y > from.y ? to.y - ROW.task / 2 : to.y + ROW.task / 2;
        // Out of the bar's lower edge near its end, clear of the title just past it.
        const d = `M${from.x2 - 6},${from.y + 12} V${midY} H${to.x1 - 10} V${to.y} H${to.x1 - 2}`;
        arrows.push(`<path class="tl-dep${clash ? ' clash' : ''}" d="${d}" marker-end="url(#tl-arrow${clash ? '-clash' : ''})"><title>${esc(pred.title)} → ${esc(r.card.title)}${clash ? ': dates clash' : ''}</title></path>`);
      }
    }

    root.innerHTML =
      `<div class="tl-toolbar">` +
      `<div class="tl-zoom" role="group" aria-label="Zoom">${Object.entries(ZOOMS).map(([k, z]) =>
        `<button type="button" class="tl-zoom-btn${k === zoom ? ' active' : ''}" data-zoom="${k}" aria-pressed="${k === zoom}">${z.label}</button>`).join('')}</div>` +
      `<button type="button" class="tl-today-btn">Today</button></div>` +
      `<div class="tl-scroll"><div class="tl-grid" style="--list:${listW}px;--chart:${chartW}px;--rows:${height}px">` +
      `<div class="tl-corner">Tasks</div>` +
      `<div class="tl-head">` +
      sc.top.map((t) => `<span class="tl-head-top" style="left:${t.x}px">${t.text}</span>`).join('') +
      sc.bottom.map((t) => `<span class="tl-head-bottom${t.weekend ? ' weekend' : ''}" style="left:${t.x}px;width:${t.w}px">${t.text}</span>`).join('') +
      `<span class="tl-today-chip" style="left:${todayX}px">Today</span></div>` +
      `<div class="tl-list">${listRows}</div>` +
      `<div class="tl-chart">` +
      sc.lines.map((l) => `<span class="tl-line${l.strong ? ' strong' : ''}" style="left:${l.x}px"></span>`).join('') +
      (zoom === 'weeks' ? sc.bottom.filter((b) => b.weekend).map((b) => `<span class="tl-weekend" style="left:${b.x}px;width:${b.w}px"></span>`).join('') : '') +
      chartRows +
      `<span class="tl-today" style="left:${todayX}px"></span>` +
      `<svg class="tl-deps" width="${chartW}" height="${height}" aria-hidden="true"><defs>` +
      `<marker id="tl-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" class="tl-arrowhead"/></marker>` +
      `<marker id="tl-arrow-clash" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" class="tl-arrowhead clash"/></marker>` +
      `</defs>${arrows.join('')}</svg>` +
      `</div></div></div>`;

    const scroller = root.querySelector('.tl-scroll');
    // First time: today a third of the way across the chart.
    if (keep) { scroller.scrollLeft = keep.left; scroller.scrollTop = keep.top; }
    else scroller.scrollLeft = Math.max(0, todayX - (scroller.clientWidth - listW) / 3);

    wire(root, board, { range, ppd, zoom, listW });
  }

  /* ---- data helpers ---- */

  function findCard(board, id) {
    for (const col of board.columns) for (const card of col.cards) if (card.id === id) return card;
    return null;
  }

  // The task waited for ends on or after the day the waiting one starts.
  function clashes(pred, card) {
    const a = pred && span(pred), b = span(card);
    return !!(a && b && a.end >= b.start);
  }

  // Every task that waits for `id`, directly or down the chain: none of them can become
  // something `id` waits for, or the chain would go round in a circle.
  function waitingOn(board, id) {
    const out = new Set();
    const stack = [id];
    while (stack.length) {
      const cur = stack.pop();
      for (const col of board.columns) {
        for (const card of col.cards) {
          if ((card.dependsOn || []).includes(cur) && !out.has(card.id)) { out.add(card.id); stack.push(card.id); }
        }
      }
    }
    return out;
  }

  // A card that's gone is waited for by nobody.
  function pruneDeps(board) {
    const ids = new Set(board.columns.flatMap((c) => c.cards.map((k) => k.id)));
    for (const col of board.columns) {
      for (const card of col.cards) {
        if (card.dependsOn?.length) card.dependsOn = card.dependsOn.filter((d) => ids.has(d));
      }
    }
  }

  // A task changed (its own `updatedAt` already stamped): saved, and the chart redrawn.
  function save(board) {
    persistBoard(board);
    render(board);
  }

  /* ---- interaction ---- */

  function wire(root, board, ctx) {
    root.querySelector('.tl-zoom').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-zoom]');
      if (!btn) return;
      setZoom(btn.dataset.zoom);
      root.querySelector('.tl-scroll').remove(); // a new scale: start again from today
      render(board);
    });
    root.querySelector('.tl-today-btn').addEventListener('click', () => {
      const scroller = root.querySelector('.tl-scroll');
      const x = (ctx.range.today - ctx.range.lo) * ctx.ppd;
      scroller.scrollTo({ left: Math.max(0, x - (scroller.clientWidth - ctx.listW) / 3), behavior: 'smooth' });
    });

    root.querySelector('.tl-list').addEventListener('click', (e) => {
      const task = e.target.closest('[data-card]');
      if (task) return openCardModal(task.dataset.card, task.dataset.col);
      const phase = e.target.closest('[data-phase]');
      if (phase) return openRenameColModal(board.columns.find((c) => c.id === phase.dataset.phase));
      const add = e.target.closest('[data-add]');
      if (add) {
        const title = prompt('Task name:');
        if (title?.trim()) addCard(add.dataset.add, title.trim());
        return;
      }
      if (e.target.closest('[data-add-phase]')) addColumn();
    });

    // A task with no dates: press a day in its row to give it some.
    root.querySelector('.tl-chart').addEventListener('click', (e) => {
      const row = e.target.closest('.tl-row-task.undated');
      if (!row) return;
      const rect = row.getBoundingClientRect();
      const day = ctx.range.lo + Math.floor((e.clientX - rect.left) / ctx.ppd);
      const card = findCard(board, row.dataset.card);
      if (!card) return;
      card.start = isoOf(day);
      card.due = isoOf(day + (card.milestone ? 0 : ZOOMS[ctx.zoom].newLength - 1));
      touch(card);
      save(board);
    });

    root.querySelectorAll('.tl-bar, .tl-milestone').forEach((el) => {
      el.addEventListener('pointerdown', (e) => startDrag(e, el, board, ctx));
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openCardModal(el.dataset.card, el.dataset.col); }
        // Arrow keys move a task a day at a time; with Shift, its end only.
        if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
          e.preventDefault();
          const card = findCard(board, el.dataset.card);
          const s = span(card);
          const d = e.key === 'ArrowLeft' ? -1 : 1;
          if (e.shiftKey && !card.milestone) setSpan(card, s.start, Math.max(s.start, s.end + d));
          else setSpan(card, s.start + d, s.end + d);
          touch(card);
          save(board);
          root.querySelector(`[data-card="${CSS.escape(card.id)}"].tl-bar, [data-card="${CSS.escape(card.id)}"].tl-milestone`)?.focus();
        }
      });
    });
  }

  function setSpan(card, start, end) {
    card.start = isoOf(start);
    card.due = isoOf(card.milestone ? start : end);
  }

  // Drag the middle of a bar to move it, an end to change its length; days snap whole. A
  // press that doesn't move opens the task, as a card does on the board.
  function startDrag(e, el, board, ctx) {
    if (e.button !== 0) return;
    const card = findCard(board, el.dataset.card);
    const s = span(card);
    if (!card || !s) return;
    const handle = e.target.closest('.tl-h');
    const mode = card.milestone || !handle ? 'move' : handle.classList.contains('tl-h-start') ? 'start' : 'end';
    const x0 = e.clientX;
    let days = 0;
    let moved = false;
    const left0 = parseFloat(el.style.left);
    const width0 = el.offsetWidth;
    el.setPointerCapture(e.pointerId);
    el.classList.add('dragging');

    const onMove = (ev) => {
      const dx = ev.clientX - x0;
      if (Math.abs(dx) > 3) moved = true;
      days = Math.round(dx / ctx.ppd);
      const len = s.end - s.start;
      if (mode === 'move') el.style.left = `${left0 + days * ctx.ppd}px`;
      else if (mode === 'start') {
        const d = Math.min(days, len);
        el.style.left = `${left0 + d * ctx.ppd}px`;
        el.style.width = `${width0 - d * ctx.ppd}px`;
      } else {
        const d = Math.max(days, -len);
        el.style.width = `${width0 + d * ctx.ppd}px`;
      }
    };
    const onUp = () => {
      el.removeEventListener('pointermove', onMove);
      el.removeEventListener('pointerup', onUp);
      el.removeEventListener('pointercancel', onUp);
      el.classList.remove('dragging');
      if (!moved) return openCardModal(card.id, el.dataset.col);
      if (!days) return render(board);
      if (mode === 'move') setSpan(card, s.start + days, s.end + days);
      else if (mode === 'start') setSpan(card, Math.min(s.start + days, s.end), s.end);
      else setSpan(card, s.start, Math.max(s.end + days, s.start));
      touch(card);
      save(board);
    };
    el.addEventListener('pointermove', onMove);
    el.addEventListener('pointerup', onUp);
    el.addEventListener('pointercancel', onUp);
  }

  window.Timeline = { render, span, waitingOn, pruneDeps, clashes, isIso };
})();
