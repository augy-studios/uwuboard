'use strict';

/* The Timeline view of a board: a Gantt chart, as Jira's Timeline draws one. The board's
   columns are its phases and their cards its tasks, so a board can switch between Kanban
   and Timeline at any time without changing what's in it.

   Each task is a bar from its start date to its due date (one day when it has only one of
   them), filled as far as its checklist is done. A milestone is a diamond on its day. Drag a
   bar to move it, or either end to change its length.

   A task can also say how the work really went: started after its due date (work that's very
   late), or given a completed date. Its bar then runs from the earliest of its dates to the
   last, and a solid stripe marks the work itself, from its start to the day it was completed,
   or to today while it's still going. A line marks the due date it ran past. The completed
   date is the day the card reached the board's last column (Done), and can be changed. Such a
   bar moves whole, every date with it. Arrows run from the tasks a task waits
   for (`dependsOn`) to it, red when the dates clash: the one waited for ends on or after the
   day the other starts. Nothing moves on its own; the red says to look. A line marks today,
   and the scale zooms between weeks, months and quarters.

   Dates are kept as YYYY-MM-DD and worked in whole days (UTC day numbers), so a clock change
   never moves a bar. Uses script.js's state and helpers (state, escapeHtml, touch, persistBoard, ...),
   so nothing here runs until script.js calls Timeline.render(). */
(function () {
  const ZOOM_KEY = 'uwuboard.timeline.zoom';
  // Each zoom level: its button label, how many pixels one day takes, how many days of
  // margin go either side of the tasks, and how long a task given dates by a press lasts.
  const ZOOMS = {
    weeks: { label: 'Weeks', pixelsPerDay: 40, margin: 7, newLength: 3 },
    months: { label: 'Months', pixelsPerDay: 14, margin: 21, newLength: 7 },
    quarters: { label: 'Quarters', pixelsPerDay: 4, margin: 45, newLength: 14 },
  };
  const ROW = { phase: 38, task: 40, add: 34 };
  const HEADER_HEIGHT = 52;
  // The colour of a task with no label of its own, by phase: Jira's blue, amber, green, then more.
  const PHASE_COLOURS = ['#4c9aff', '#ffb31f', '#36b37e', '#ff7452', '#998dd9', '#00b8d9'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DAYS_OF_WEEK = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  /* ---- dates as day numbers ---- */

  const MILLISECONDS_PER_DAY = 86400000;
  const isIsoDate = (text) => {
    return typeof text === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(text);
  };
  const dayOf = (iso) => {
    const [year, month, day] = iso.split('-').map(Number);
    return Math.round(Date.UTC(year, month - 1, day) / MILLISECONDS_PER_DAY);
  };
  const isoDateOf = (dayNumber) => {
    return new Date(dayNumber * MILLISECONDS_PER_DAY).toISOString().slice(0, 10);
  };
  const dateOf = (dayNumber) => {
    return new Date(dayNumber * MILLISECONDS_PER_DAY);
  };
  function todayIsoDate() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  }
  // A day number as a short date, such as "5 Mar".
  const formatDay = (dayNumber) => {
    const date = dateOf(dayNumber);
    return `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
  };

  // A task's span as day numbers, or null without dates: the whole bar, the work as it went
  // included. One date alone is a one-day task; a milestone is always one day, on its due date.
  function span(card, today = todayIsoDate()) {
    let startDay = null;
    if (isIsoDate(card.start)) {
      startDay = dayOf(card.start);
    }
    let dueDay = null;
    if (isIsoDate(card.due)) {
      dueDay = dayOf(card.due);
    }
    if (startDay === null && dueDay === null) {
      return null;
    }
    if (card.milestone) {
      let day = dueDay;
      if (day === null || day === undefined) {
        day = startDay;
      }
      return { start: day, end: day };
    }
    let start = startDay;
    if (start === null || start === undefined) {
      start = dueDay;
    }
    let end = dueDay;
    if (end === null || end === undefined) {
      end = startDay;
    }
    let plan;
    if (start <= end) {
      plan = { start, end };
    } else {
      plan = { start: end, end: start };
    }
    const actualSpan = actual(card, today);
    if (!actualSpan) {
      return plan;
    }
    return { start: Math.min(plan.start, actualSpan.start), end: Math.max(plan.end, actualSpan.end) };
  }

  // The work as it went, for a task started after its due date or given a completed date: from
  // its start to the day it was completed, or to today while it's still going. Otherwise null.
  function actual(card, today = todayIsoDate()) {
    if (card.milestone || !isIsoDate(card.start)) {
      return null;
    }
    const startedLate = isIsoDate(card.due) && card.start > card.due;
    if (!startedLate && !isIsoDate(card.completed)) {
      return null;
    }
    const startDay = dayOf(card.start);
    let endDate = today;
    if (isIsoDate(card.completed)) {
      endDate = card.completed;
    }
    return { start: startDay, end: Math.max(startDay, dayOf(endDate)) };
  }

  // How much of a task's checklist is done, from 0 to 1 (0 when it has no checklist).
  function progress(card) {
    let checklist = card.checklist;
    if (!checklist) {
      checklist = [];
    }
    if (checklist.length) {
      const doneCount = checklist.filter((item) => {
        return item.done;
      }).length;
      return doneCount / checklist.length;
    } else {
      return 0;
    }
  }

  // Late: past its due date, not completed and not all ticked off. Never a milestone.
  function isLate(card, today = todayIsoDate()) {
    return !card.milestone && isIsoDate(card.due) && card.due < today && !isIsoDate(card.completed) && progress(card) < 1;
  }

  // A task's dates as its row says them.
  function when(card, today = todayIsoDate()) {
    const taskSpan = span(card, today);
    if (!taskSpan) {
      return 'No dates';
    }
    const actualSpan = actual(card, today);
    if (actualSpan) {
      let work;
      if (!isIsoDate(card.completed)) {
        work = `${formatDay(actualSpan.start)} – now`;
      } else if (actualSpan.start === actualSpan.end) {
        work = formatDay(actualSpan.start);
      } else {
        work = `${formatDay(actualSpan.start)} – ${formatDay(actualSpan.end)}`;
      }
      if (isIsoDate(card.due)) {
        return `Due ${formatDay(dayOf(card.due))} · ${work}`;
      } else {
        return work;
      }
    }
    if (taskSpan.start === taskSpan.end) {
      return formatDay(taskSpan.start);
    } else {
      return `${formatDay(taskSpan.start)} – ${formatDay(taskSpan.end)}`;
    }
  }

  // The day a card reached the board's last column (Done; Release on a timeline) is its
  // completed date: set as it arrives (or is added there), cleared if it leaves. Moves within
  // a column, or between two others, leave it be.
  function stampCompleted(board, card, fromColumnId, toColumnId, today = todayIsoDate()) {
    if (fromColumnId === toColumnId) {
      return;
    }
    const lastColumn = board.columns[board.columns.length - 1];
    if (!lastColumn) {
      return;
    }
    if (toColumnId === lastColumn.id) {
      card.completed = today;
    } else if (fromColumnId === lastColumn.id) {
      delete card.completed;
    }
  }

  // Every date a task has, moved by `days`: a bar that shows the work as it went moves whole.
  function shift(card, days) {
    for (const key of ['start', 'due', 'completed']) {
      if (isIsoDate(card[key])) {
        card[key] = isoDateOf(dayOf(card[key]) + days);
      }
    }
  }

  /* ---- zoom ---- */

  function getZoom() {
    try {
      const storedZoom = localStorage.getItem(ZOOM_KEY);
      if (ZOOMS[storedZoom]) {
        return storedZoom;
      }
    } catch { /* the default */ }
    return 'months';
  }
  function setZoom(zoom) {
    try { localStorage.setItem(ZOOM_KEY, zoom); } catch { /* this visit only */ }
  }

  /* ---- layout ---- */

  // The colour of a task's bar: its first label's colour, or failing that its phase's colour.
  function taskColour(card, phaseIndex) {
    let colour;
    const labels = card.labels;
    if (labels !== null && labels !== undefined) {
      const firstLabel = labels[0];
      if (firstLabel !== null && firstLabel !== undefined) {
        colour = firstLabel.color;
      }
    }
    if (!colour) {
      colour = PHASE_COLOURS[phaseIndex % PHASE_COLOURS.length];
    }
    return colour;
  }

  // The rows top to bottom: each phase, its tasks, and a row to add one; then one to add a phase.
  function rowsOf(board) {
    const rows = [];
    let y = 0;
    board.columns.forEach((column, phaseIndex) => {
      rows.push({ kind: 'phase', column, colour: PHASE_COLOURS[phaseIndex % PHASE_COLOURS.length], y, height: ROW.phase });
      y = y + ROW.phase;
      for (const card of column.cards) {
        rows.push({ kind: 'task', column, card, colour: taskColour(card, phaseIndex), y, height: ROW.task });
        y = y + ROW.task;
      }
      rows.push({ kind: 'add', column, y, height: ROW.add });
      y = y + ROW.add;
    });
    rows.push({ kind: 'addPhase', y, height: ROW.add });
    y = y + ROW.add;
    return { rows, height: y };
  }

  // The days on show: every task and today, with a margin, from the start of a week (Monday)
  // or month, and wide enough to fill the space there is.
  function rangeOf(board, zoom, minWidth) {
    const zoomSettings = ZOOMS[zoom];
    const today = dayOf(todayIsoDate());
    let firstDay = today;
    let lastDay = today;
    for (const column of board.columns) {
      for (const card of column.cards) {
        const taskSpan = span(card);
        if (taskSpan) {
          firstDay = Math.min(firstDay, taskSpan.start);
          lastDay = Math.max(lastDay, taskSpan.end);
        }
      }
    }
    firstDay = firstDay - zoomSettings.margin;
    lastDay = lastDay + zoomSettings.margin;
    const firstDate = dateOf(firstDay);
    if (zoom === 'weeks') {
      firstDay = firstDay - (firstDate.getUTCDay() + 6) % 7;
    } else {
      firstDay = Math.round(Date.UTC(firstDate.getUTCFullYear(), firstDate.getUTCMonth(), 1) / MILLISECONDS_PER_DAY);
    }
    const days = Math.max(lastDay - firstDay + 1, Math.ceil(minWidth / zoomSettings.pixelsPerDay));
    return { lo: firstDay, days, today };
  }

  /* ---- drawing ---- */

  // The two rows of the header and the gridlines under them.
  function scale(range, zoom) {
    const { pixelsPerDay } = ZOOMS[zoom];
    const top = [];
    const bottom = [];
    const lines = [];
    let lastTop = null;
    for (let dayNumber = range.lo; dayNumber < range.lo + range.days; dayNumber = dayNumber + 1) {
      const date = dateOf(dayNumber);
      const x = (dayNumber - range.lo) * pixelsPerDay;
      const month = date.getUTCMonth();
      const year = date.getUTCFullYear();
      const day = date.getUTCDate();
      // The top row names a quarter or a month, and gets a new entry whenever that changes.
      let topKey;
      if (zoom === 'quarters') {
        topKey = `${year}Q${Math.floor(month / 3)}`;
      } else {
        topKey = `${year}-${month}`;
      }
      if (topKey !== lastTop) {
        let topText;
        if (zoom === 'quarters') {
          topText = `Q${Math.floor(month / 3) + 1} ${year}`;
        } else {
          topText = `${MONTHS[month]} ${year}`;
        }
        top.push({ x, text: topText });
        lastTop = topKey;
      }
      if (zoom === 'weeks') {
        bottom.push({ x, width: pixelsPerDay, text: `${DAYS_OF_WEEK[date.getUTCDay()]} ${day}`, weekend: date.getUTCDay() % 6 === 0 });
        lines.push({ x, strong: date.getUTCDay() === 1 });
      } else if (zoom === 'months' && date.getUTCDay() === 1) {
        bottom.push({ x, width: 7 * pixelsPerDay, text: `${day}` });
        lines.push({ x, strong: day <= 7 });
      } else if (zoom === 'quarters' && day === 1) {
        bottom.push({ x, width: 30 * pixelsPerDay, text: MONTHS[month] });
        lines.push({ x, strong: month % 3 === 0 });
      }
    }
    return { top, bottom, lines };
  }

  // The board on show, and the width it was drawn for: a chart drawn before it had any room
  // (the app still hidden as a board opens), or for a different width, is drawn again.
  let current = null;
  let drawnWidth = 0;
  let sizer = null;

  function watchSize(root) {
    if (sizer) {
      return;
    }
    sizer = new ResizeObserver(() => {
      const width = root.clientWidth;
      if (!current || root.classList.contains('hidden') || !width || width === drawnWidth) {
        return;
      }
      let activeBoard;
      if (getActiveBoard !== null && getActiveBoard !== undefined) {
        activeBoard = getActiveBoard();
      }
      if (current !== activeBoard) {
        return;
      }
      render(current);
    });
    sizer.observe(root);
  }

  // The left-hand list's button for one row: a phase, a task, or one of the add buttons.
  function listRowHtml(row) {
    const style = `top:${row.y}px;height:${row.height}px`;
    if (row.kind === 'phase') {
      return `<button type="button" class="tl-phase" style="${style}" data-phase="${escapeHtml(row.column.id)}" title="Rename or delete this phase">` +
        `<span class="tl-swatch" style="background:${row.colour}"></span><span class="tl-name">${escapeHtml(row.column.name)}</span>` +
        `<span class="tl-count">${row.column.cards.length}</span></button>`;
    }
    if (row.kind === 'task') {
      const taskSpan = span(row.card);
      let undatedClass;
      if (taskSpan) {
        undatedClass = '';
      } else {
        undatedClass = ' undated';
      }
      let diamond;
      if (row.card.milestone) {
        diamond = '<span class="tl-diamond-sm" aria-hidden="true"></span>';
      } else {
        diamond = '';
      }
      return `<button type="button" class="tl-task${undatedClass}" style="${style}" data-card="${escapeHtml(row.card.id)}" data-col="${escapeHtml(row.column.id)}">` +
        `<span class="tl-name">${diamond}${escapeHtml(row.card.title)}</span>` +
        `<span class="tl-when">${when(row.card)}</span></button>`;
    }
    if (row.kind === 'add') {
      return `<button type="button" class="tl-add" style="${style}" data-add="${escapeHtml(row.column.id)}">+ Add task</button>`;
    }
    return `<button type="button" class="tl-add tl-add-phase" style="${style}" data-add-phase>+ Add phase</button>`;
  }

  // Draws the whole chart for `board` into the timeline container: the zoom toolbar, the
  // header with its dates, the list of phases and tasks on the left, and on the right the
  // bars, milestones, phase roll-ups, today's line and the dependency arrows. Then it puts
  // the scroll position back (or scrolls to today the first time) and wires up the events.
  function render(board) {
    const root = document.getElementById('timeline-container');
    watchSize(root);
    const oldScroller = root.querySelector('.tl-scroll');
    // Where it was scrolled to, kept across a redraw; not from a chart drawn with no room,
    // which never scrolled anywhere.
    let savedScroll = null;
    if (oldScroller && drawnWidth) {
      savedScroll = { left: oldScroller.scrollLeft, top: oldScroller.scrollTop };
    }
    current = board;
    drawnWidth = root.clientWidth;
    const zoom = getZoom();
    const { pixelsPerDay } = ZOOMS[zoom];
    let listWidth;
    if (window.innerWidth <= 720) {
      listWidth = 132;
    } else {
      listWidth = 240;
    }
    const minWidth = Math.max(root.clientWidth - listWidth, 320);
    const range = rangeOf(board, zoom, minWidth);
    const chartWidth = range.days * pixelsPerDay;
    const { rows, height } = rowsOf(board);
    const scaleMarks = scale(range, zoom);
    const xOfDay = (dayNumber) => {
      return (dayNumber - range.lo) * pixelsPerDay;
    };
    const todayX = xOfDay(range.today) + pixelsPerDay / 2;

    const listRows = rows.map(listRowHtml).join('');

    // Row stripes, bars, milestones and phase roll-ups.
    const bars = new Map(); // card id -> { startX, endX, y }
    const chartRows = rows.map((row) => {
      if (row.kind === 'phase') {
        // Not map(span): map would pass the index as span's `today`.
        const spans = row.column.cards.map((card) => {
          return span(card);
        }).filter(Boolean);
        if (!spans.length) {
          return `<div class="tl-row tl-row-phase" style="top:${row.y}px;height:${row.height}px"></div>`;
        }
        const firstDay = Math.min(...spans.map((taskSpan) => {
          return taskSpan.start;
        }));
        const lastDay = Math.max(...spans.map((taskSpan) => {
          return taskSpan.end;
        }));
        return `<div class="tl-row tl-row-phase" style="top:${row.y}px;height:${row.height}px">` +
          `<span class="tl-rollup" style="left:${xOfDay(firstDay)}px;width:${(lastDay - firstDay + 1) * pixelsPerDay}px;background:${row.colour}" title="${escapeHtml(row.column.name)}: ${formatDay(firstDay)} – ${formatDay(lastDay)}"></span></div>`;
      }
      if (row.kind !== 'task') {
        return '';
      }
      const taskSpan = span(row.card);
      const id = escapeHtml(row.card.id);
      if (!taskSpan) {
        return `<div class="tl-row tl-row-task undated" style="top:${row.y}px;height:${row.height}px" data-card="${id}" data-col="${escapeHtml(row.column.id)}" title="Press a day to give “${escapeHtml(row.card.title)}” dates"></div>`;
      }
      const startX = xOfDay(taskSpan.start);
      const endX = xOfDay(taskSpan.end) + pixelsPerDay;
      const centreY = row.y + row.height / 2;
      bars.set(row.card.id, { startX, endX, y: centreY });
      const late = isLate(row.card);
      if (row.card.milestone) {
        return `<div class="tl-row tl-row-task" style="top:${row.y}px;height:${row.height}px">` +
          `<div class="tl-milestone" style="left:${startX + pixelsPerDay / 2 - 11}px" data-card="${id}" data-col="${escapeHtml(row.column.id)}" tabindex="0" role="button" aria-label="${escapeHtml(row.card.title)}, milestone, ${formatDay(taskSpan.start)}">` +
          `<span class="tl-diamond" style="background:${row.colour}"></span><span class="tl-label">${escapeHtml(row.card.title)}</span></div></div>`;
      }
      let lateClass;
      let lateText;
      if (late) {
        lateClass = ' late';
        lateText = ' (late)';
      } else {
        lateClass = '';
        lateText = '';
      }
      // The title just past the bar's end, where it reads whatever the bar's colour.
      // A late task says so in words, not only with its red edge (WCAG 1.4.1).
      const label = `<span class="tl-label${lateClass}" style="left:${endX + 8}px">${escapeHtml(row.card.title)}${lateText}</span>`;
      const percentDone = Math.round(progress(row.card) * 100);
      let checklist = row.card.checklist;
      if (!checklist) {
        checklist = [];
      }
      const actualSpan = actual(row.card);
      // The work as it went, in place of the checklist's fill: a solid stripe from its start to
      // its completion (or today), and a line at the due date it ran past. It moves whole.
      let inside;
      let said;
      if (actualSpan) {
        let dueDay = null;
        if (isIsoDate(row.card.due)) {
          dueDay = dayOf(row.card.due);
        }
        inside = `<span class="tl-actual" style="left:${(actualSpan.start - taskSpan.start) * pixelsPerDay}px;width:${(actualSpan.end - actualSpan.start + 1) * pixelsPerDay}px"></span>`;
        if (dueDay !== null && dueDay < taskSpan.end) {
          inside += `<span class="tl-due-mark" style="left:${(dueDay - taskSpan.start + 1) * pixelsPerDay - 1}px"></span>`;
        }
        said = '';
        if (dueDay !== null) {
          said += `, due ${formatDay(dueDay)}`;
        }
        said += `, started ${formatDay(actualSpan.start)}`;
        if (isIsoDate(row.card.completed)) {
          said += `, completed ${formatDay(actualSpan.end)}`;
        } else {
          said += ', still going';
        }
      } else {
        inside = `<span class="tl-fill" style="width:${percentDone}%"></span><span class="tl-h tl-h-start" aria-hidden="true"></span><span class="tl-h tl-h-end" aria-hidden="true"></span>`;
        let doneText;
        if (checklist.length) {
          doneText = `, ${percentDone}% done`;
        } else {
          doneText = '';
        }
        said = `, ${formatDay(taskSpan.start)} to ${formatDay(taskSpan.end)}${doneText}`;
      }
      let actualClass;
      if (actualSpan) {
        actualClass = ' has-actual';
      } else {
        actualClass = '';
      }
      let lateSaid;
      if (late) {
        lateSaid = ', late';
      } else {
        lateSaid = '';
      }
      return `<div class="tl-row tl-row-task" style="top:${row.y}px;height:${row.height}px">` +
        `<div class="tl-bar${lateClass}${actualClass}" style="left:${startX}px;width:${endX - startX}px;--bar:${row.colour}" data-card="${id}" data-col="${escapeHtml(row.column.id)}" tabindex="0" role="button" ` +
        `aria-label="${escapeHtml(row.card.title)}${said}${lateSaid}">` +
        inside + '</div>' +
        label + '</div>';
    }).join('');

    // Dependency arrows, from the end of the task waited for to the start of the one waiting.
    const arrows = [];
    for (const row of rows) {
      if (row.kind !== 'task' || !bars.has(row.card.id)) {
        continue;
      }
      let dependsOn = row.card.dependsOn;
      if (!dependsOn) {
        dependsOn = [];
      }
      for (const dependencyId of dependsOn) {
        const from = bars.get(dependencyId);
        if (!from) {
          continue;
        }
        const to = bars.get(row.card.id);
        const predecessor = findCard(board, dependencyId);
        const clash = clashes(predecessor, row.card);
        let midY;
        if (to.y > from.y) {
          midY = to.y - ROW.task / 2;
        } else {
          midY = to.y + ROW.task / 2;
        }
        // Out of the bar's lower edge near its end, clear of the title just past it.
        const pathData = `M${from.endX - 6},${from.y + 12} V${midY} H${to.startX - 10} V${to.y} H${to.startX - 2}`;
        let clashClass;
        let markerSuffix;
        let clashTitle;
        if (clash) {
          clashClass = ' clash';
          markerSuffix = '-clash';
          clashTitle = ': dates clash';
        } else {
          clashClass = '';
          markerSuffix = '';
          clashTitle = '';
        }
        arrows.push(`<path class="tl-dep${clashClass}" d="${pathData}" marker-end="url(#tl-arrow${markerSuffix})"><title>${escapeHtml(predecessor.title)} → ${escapeHtml(row.card.title)}${clashTitle}</title></path>`);
      }
    }

    // The pieces of the page around the rows: zoom buttons, header labels, gridlines and,
    // on the weekly scale, the weekend stripes.
    const zoomButtons = Object.entries(ZOOMS).map(([zoomName, zoomSettings]) => {
      let activeClass;
      if (zoomName === zoom) {
        activeClass = ' active';
      } else {
        activeClass = '';
      }
      return `<button type="button" class="tl-zoom-btn${activeClass}" data-zoom="${zoomName}" aria-pressed="${zoomName === zoom}">${zoomSettings.label}</button>`;
    }).join('');
    const headTop = scaleMarks.top.map((mark) => {
      return `<span class="tl-head-top" style="left:${mark.x}px">${mark.text}</span>`;
    }).join('');
    const headBottom = scaleMarks.bottom.map((mark) => {
      let weekendClass;
      if (mark.weekend) {
        weekendClass = ' weekend';
      } else {
        weekendClass = '';
      }
      return `<span class="tl-head-bottom${weekendClass}" style="left:${mark.x}px;width:${mark.width}px">${mark.text}</span>`;
    }).join('');
    const gridLines = scaleMarks.lines.map((line) => {
      let strongClass;
      if (line.strong) {
        strongClass = ' strong';
      } else {
        strongClass = '';
      }
      return `<span class="tl-line${strongClass}" style="left:${line.x}px"></span>`;
    }).join('');
    let weekendStripes;
    if (zoom === 'weeks') {
      weekendStripes = scaleMarks.bottom.filter((mark) => {
        return mark.weekend;
      }).map((mark) => {
        return `<span class="tl-weekend" style="left:${mark.x}px;width:${mark.width}px"></span>`;
      }).join('');
    } else {
      weekendStripes = '';
    }

    root.innerHTML =
      `<div class="tl-toolbar">` +
      `<div class="tl-zoom" role="group" aria-label="Zoom">${zoomButtons}</div>` +
      `<button type="button" class="tl-today-btn">Today</button></div>` +
      `<div class="tl-scroll"><div class="tl-grid" style="--list:${listWidth}px;--chart:${chartWidth}px;--rows:${height}px">` +
      `<div class="tl-corner">Tasks</div>` +
      `<div class="tl-head">` +
      headTop +
      headBottom +
      `<span class="tl-today-chip" style="left:${todayX}px">Today</span></div>` +
      `<div class="tl-list">${listRows}</div>` +
      `<div class="tl-chart">` +
      gridLines +
      weekendStripes +
      chartRows +
      `<span class="tl-today" style="left:${todayX}px"></span>` +
      `<svg class="tl-deps" width="${chartWidth}" height="${height}" aria-hidden="true"><defs>` +
      `<marker id="tl-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" class="tl-arrowhead"/></marker>` +
      `<marker id="tl-arrow-clash" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" class="tl-arrowhead clash"/></marker>` +
      `</defs>${arrows.join('')}</svg>` +
      `</div></div></div>`;

    const scroller = root.querySelector('.tl-scroll');
    // First time: today a third of the way across the chart.
    if (savedScroll) {
      scroller.scrollLeft = savedScroll.left;
      scroller.scrollTop = savedScroll.top;
    } else {
      scroller.scrollLeft = Math.max(0, todayX - (scroller.clientWidth - listWidth) / 3);
    }

    wire(root, board, { range, pixelsPerDay, zoom, listWidth });
  }

  /* ---- data helpers ---- */

  function findCard(board, id) {
    for (const column of board.columns) {
      for (const card of column.cards) {
        if (card.id === id) {
          return card;
        }
      }
    }
    return null;
  }

  // The task waited for ends on or after the day the waiting one starts.
  function clashes(predecessor, card) {
    let predecessorSpan = predecessor;
    if (predecessor) {
      predecessorSpan = span(predecessor);
    }
    const cardSpan = span(card);
    if (!predecessorSpan || !cardSpan) {
      return false;
    }
    return predecessorSpan.end >= cardSpan.start;
  }

  // Every task that waits for `id`, directly or down the chain: none of them can become
  // something `id` waits for, or the chain would go round in a circle.
  function waitingOn(board, id) {
    const waiting = new Set();
    const stack = [id];
    while (stack.length) {
      const currentId = stack.pop();
      for (const column of board.columns) {
        for (const card of column.cards) {
          let dependsOn = card.dependsOn;
          if (!dependsOn) {
            dependsOn = [];
          }
          if (dependsOn.includes(currentId) && !waiting.has(card.id)) {
            waiting.add(card.id);
            stack.push(card.id);
          }
        }
      }
    }
    return waiting;
  }

  // A card that's gone is waited for by nobody.
  function pruneDependencies(board) {
    const ids = new Set(board.columns.flatMap((column) => {
      return column.cards.map((card) => {
        return card.id;
      });
    }));
    for (const column of board.columns) {
      for (const card of column.cards) {
        if (card.dependsOn !== null && card.dependsOn !== undefined && card.dependsOn.length) {
          card.dependsOn = card.dependsOn.filter((dependencyId) => {
            return ids.has(dependencyId);
          });
        }
      }
    }
  }

  // A task changed (its own `updatedAt` already stamped): saved, and the chart redrawn.
  function save(board) {
    persistBoard(board);
    render(board);
  }

  /* ---- interaction ---- */

  // Hooks up everything in a freshly drawn chart: the zoom and Today buttons, the list on the
  // left (open a task, rename a phase, add a task or phase), pressing a day in an undated
  // task's row, and dragging or arrow-keying the bars and milestones.
  function wire(root, board, layout) {
    root.querySelector('.tl-zoom').addEventListener('click', (event) => {
      const button = event.target.closest('[data-zoom]');
      if (!button) {
        return;
      }
      setZoom(button.dataset.zoom);
      root.querySelector('.tl-scroll').remove(); // a new scale: start again from today
      render(board);
    });
    root.querySelector('.tl-today-btn').addEventListener('click', () => {
      const scroller = root.querySelector('.tl-scroll');
      const x = (layout.range.today - layout.range.lo) * layout.pixelsPerDay;
      scroller.scrollTo({ left: Math.max(0, x - (scroller.clientWidth - layout.listWidth) / 3), behavior: 'smooth' });
    });

    root.querySelector('.tl-list').addEventListener('click', (event) => {
      const task = event.target.closest('[data-card]');
      if (task) {
        openCardModal(task.dataset.card, task.dataset.col);
        return;
      }
      const phase = event.target.closest('[data-phase]');
      if (phase) {
        openRenameColumnModal(board.columns.find((column) => {
          return column.id === phase.dataset.phase;
        }));
        return;
      }
      const add = event.target.closest('[data-add]');
      if (add) {
        const title = prompt('Task name:');
        if (title !== null && title !== undefined && title.trim()) {
          addCard(add.dataset.add, title.trim());
        }
        return;
      }
      if (event.target.closest('[data-add-phase]')) {
        addColumn();
      }
    });

    // A task with no dates: press a day in its row to give it some.
    root.querySelector('.tl-chart').addEventListener('click', (event) => {
      const row = event.target.closest('.tl-row-task.undated');
      if (!row) {
        return;
      }
      const rect = row.getBoundingClientRect();
      const day = layout.range.lo + Math.floor((event.clientX - rect.left) / layout.pixelsPerDay);
      const card = findCard(board, row.dataset.card);
      if (!card) {
        return;
      }
      card.start = isoDateOf(day);
      let extraDays;
      if (card.milestone) {
        extraDays = 0;
      } else {
        extraDays = ZOOMS[layout.zoom].newLength - 1;
      }
      card.due = isoDateOf(day + extraDays);
      touch(card);
      save(board);
    });

    root.querySelectorAll('.tl-bar, .tl-milestone').forEach((element) => {
      element.addEventListener('pointerdown', (event) => {
        return startDrag(event, element, board, layout);
      });
      element.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          openCardModal(element.dataset.card, element.dataset.col);
        }
        // Arrow keys move a task a day at a time; with Shift, its end only.
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          event.preventDefault();
          const card = findCard(board, element.dataset.card);
          const taskSpan = span(card);
          let step;
          if (event.key === 'ArrowLeft') {
            step = -1;
          } else {
            step = 1;
          }
          if (actual(card)) {
            shift(card, step);
          } else if (event.shiftKey && !card.milestone) {
            setSpan(card, taskSpan.start, Math.max(taskSpan.start, taskSpan.end + step));
          } else {
            setSpan(card, taskSpan.start + step, taskSpan.end + step);
          }
          touch(card);
          save(board);
          const redrawn = root.querySelector(`[data-card="${CSS.escape(card.id)}"].tl-bar, [data-card="${CSS.escape(card.id)}"].tl-milestone`);
          if (redrawn !== null && redrawn !== undefined) {
            redrawn.focus();
          }
        }
      });
    });
  }

  function setSpan(card, start, end) {
    card.start = isoDateOf(start);
    if (card.milestone) {
      card.due = isoDateOf(start);
    } else {
      card.due = isoDateOf(end);
    }
  }

  // Drag the middle of a bar to move it, an end to change its length; days snap whole. A
  // press that doesn't move opens the task, as a card does on the board.
  function startDrag(event, element, board, layout) {
    if (event.button !== 0) {
      return;
    }
    const card = findCard(board, element.dataset.card);
    const taskSpan = span(card);
    if (!card || !taskSpan) {
      return;
    }
    const handle = event.target.closest('.tl-h');
    // A bar that shows the work as it went moves whole, every date with it.
    const whole = Boolean(actual(card));
    let mode;
    if (card.milestone || whole || !handle) {
      mode = 'move';
    } else if (handle.classList.contains('tl-h-start')) {
      mode = 'start';
    } else {
      mode = 'end';
    }
    const startX = event.clientX;
    let days = 0;
    let moved = false;
    const startLeft = parseFloat(element.style.left);
    const startWidth = element.offsetWidth;
    element.setPointerCapture(event.pointerId);
    element.classList.add('dragging');

    // While dragging: the bar follows the pointer a whole day at a time, without saving yet.
    const onMove = (moveEvent) => {
      const deltaX = moveEvent.clientX - startX;
      if (Math.abs(deltaX) > 3) {
        moved = true;
      }
      days = Math.round(deltaX / layout.pixelsPerDay);
      const spanLength = taskSpan.end - taskSpan.start;
      if (mode === 'move') {
        element.style.left = `${startLeft + days * layout.pixelsPerDay}px`;
      } else if (mode === 'start') {
        const clampedDays = Math.min(days, spanLength);
        element.style.left = `${startLeft + clampedDays * layout.pixelsPerDay}px`;
        element.style.width = `${startWidth - clampedDays * layout.pixelsPerDay}px`;
      } else {
        const clampedDays = Math.max(days, -spanLength);
        element.style.width = `${startWidth + clampedDays * layout.pixelsPerDay}px`;
      }
    };
    // Letting go: a press that never moved opens the task; otherwise the new dates are saved.
    const onUp = () => {
      element.removeEventListener('pointermove', onMove);
      element.removeEventListener('pointerup', onUp);
      element.removeEventListener('pointercancel', onUp);
      element.classList.remove('dragging');
      if (!moved) {
        openCardModal(card.id, element.dataset.col);
        return;
      }
      if (!days) {
        render(board);
        return;
      }
      if (whole) {
        shift(card, days);
      } else if (mode === 'move') {
        setSpan(card, taskSpan.start + days, taskSpan.end + days);
      } else if (mode === 'start') {
        setSpan(card, Math.min(taskSpan.start + days, taskSpan.end), taskSpan.end);
      } else {
        setSpan(card, taskSpan.start, Math.max(taskSpan.end + days, taskSpan.start));
      }
      touch(card);
      save(board);
    };
    element.addEventListener('pointermove', onMove);
    element.addEventListener('pointerup', onUp);
    element.addEventListener('pointercancel', onUp);
  }

  window.Timeline = { render, span, actual, isLate, when, shift, stampCompleted, waitingOn, pruneDependencies, clashes, isIsoDate };
})();
