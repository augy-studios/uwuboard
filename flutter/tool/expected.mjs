// Runs the site's own JavaScript (main-site/js/timeline.js and sync.js) on fixed inputs and writes
// what it answers to test/fixtures/expected.json, which test/parity_test.dart compares the Dart
// ports (lib/data/timeline_logic.dart, lib/data/sync_logic.dart) with. Run it again whenever
// either side changes:
//
//     node tool/expected.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, '../../main-site/js');

// timeline.js: its exported helpers, with the page it would touch stubbed out.
const ctx = { window: {}, document: { getElementById: () => null }, localStorage: { getItem: () => null, setItem() {} }, console, Event: class {} };
vm.createContext(ctx);
vm.runInContext(readFileSync(join(site, 'timeline.js'), 'utf8'), ctx);
const T = ctx.window.Timeline;
vm.runInContext(readFileSync(join(site, 'markdown.js'), 'utf8'), ctx);
const M = ctx.window.Markdown;

// sync.js keeps its helpers inside its closure: the pure ones are lifted out by name.
const syncSrc = readFileSync(join(site, 'sync.js'), 'utf8');
const grab = (name) => {
  const start = syncSrc.indexOf(`function ${name}(`);
  if (start < 0) throw new Error(`no function ${name} in sync.js`);
  let depth = 0;
  for (let i = syncSrc.indexOf('{', start); i < syncSrc.length; i++) {
    if (syncSrc[i] === '{') depth++;
    if (syncSrc[i] === '}' && --depth === 0) return syncSrc.slice(start, i + 1);
  }
  throw new Error(`unbalanced ${name}`);
};
// A `const name = …;`, however many lines it runs to.
const constLine = (name) => {
  const start = syncSrc.indexOf(`const ${name} = `);
  if (start < 0) throw new Error(`no const ${name} in sync.js`);
  let depth = 0;
  for (let i = start; i < syncSrc.length; i++) {
    const ch = syncSrc[i];
    if ('([{'.includes(ch)) depth++;
    if (')]}'.includes(ch)) depth--;
    if (ch === ';' && depth === 0) return syncSrc.slice(start, i + 1);
  }
  throw new Error(`unended ${name}`);
};
const lifted = [
  'MAX_BOARDS', 'MAX_COLUMNS', 'MAX_CARDS', 'MAX_IMAGES', 'ID_RE', 'isId', 'text', 'list', 'PRIORITIES', 'clone', 'stamp', 'cardSig',
].map(constLine).join('\n') + '\n' + ['cleanCard', 'cleanBoards', 'mergeBoardInto', 'wouldChange'].map(grab).join('\n');
const S = {};
vm.runInNewContext(`${lifted}\nout.cleanBoards = cleanBoards; out.mergeBoardInto = mergeBoardInto; out.wouldChange = wouldChange; out.clone = clone;`, { out: S, JSON });

const card = (id, title, extra = {}) => ({ id, title, description: '', labels: [], checklist: [], due: '', priority: '', images: [], thumbnailId: null, updatedAt: 10, ...extra });

// ---- Timeline ----
const spanCards = [
  card('a', 'Both', { start: '2026-03-01', due: '2026-03-05' }),
  card('b', 'Due only', { due: '2026-03-07' }),
  card('c', 'Start only', { start: '2026-02-27' }),
  card('d', 'Backwards', { start: '2026-03-09', due: '2026-03-02' }),
  card('e', 'Milestone', { start: '2026-03-01', due: '2026-03-10', milestone: true }),
  card('f', 'None'),
  card('g', 'Bad dates', { start: '2026-3-1', due: 'soon' }),
  card('h', 'Started late, done', { start: '2026-03-12', due: '2026-03-05', completed: '2026-03-15' }),
  card('i', 'Done early', { start: '2026-03-01', due: '2026-03-10', completed: '2026-03-06' }),
  card('j', 'Ran over', { start: '2026-03-01', due: '2026-03-05', completed: '2026-03-08' }),
  card('k', 'Done before it started', { start: '2026-03-10', completed: '2026-03-08' }),
  card('l', 'Ticked off', { start: '2026-03-01', due: '2026-03-05', checklist: [{ text: 'x', done: true }] }),
];
// "Today" for the answers that depend on it: a task still going runs to it.
const today = '2026-03-20';
const board = {
  id: 'b1', name: 'Plan', view: 'timeline', columns: [
    { id: 'p1', name: 'Design', cards: [spanCards[0], { ...spanCards[1], dependsOn: ['a'] }] },
    { id: 'p2', name: 'Build', cards: [{ ...spanCards[2], dependsOn: ['b'] }, spanCards[3], spanCards[4], spanCards[5]] },
  ],
};
const timeline = {
  spans: spanCards.map((c) => ({ id: c.id, span: T.span(c, today) })),
  actual: spanCards.map((c) => ({ id: c.id, actual: T.actual(c, today) })),
  when: spanCards.map((c) => ({ id: c.id, when: T.when(c, today) })),
  late: spanCards.map((c) => ({ id: c.id, late: T.isLate(c, today) })),
  // Into the last column (Done) completed today, out of it cleared, other moves left be.
  stamped: [
    ['p1', 'p2', null], ['p2', 'p1', '2026-03-01'], ['p1', 'p1', null], [null, 'p2', null], [null, 'p1', '2026-03-01'],
  ].map(([from, to, had]) => {
    const k = card('s', 'Moving', had ? { completed: had } : {});
    T.stampCompleted(board, k, from, to, today);
    return { from, to, had, completed: k.completed ?? null };
  }),
  shifted: spanCards.map((c) => { const k = S.clone(c); T.shift(k, 3); return { id: c.id, start: k.start ?? null, due: k.due, completed: k.completed ?? null }; }),
  clashes: [
    ['a', 'b'], ['b', 'c'], ['a', 'f'],
  ].map(([p, k]) => {
    const all = board.columns.flatMap((c) => c.cards);
    return { pred: p, card: k, clash: T.clashes(all.find((x) => x.id === p), all.find((x) => x.id === k)) };
  }),
  waitingOn: ['a', 'b', 'c'].map((id) => ({ id, waiting: [...T.waitingOn(board, id)].sort() })),
};
const pruned = S.clone(board);
pruned.columns[0].cards.splice(0, 1);
T.pruneDeps(pruned);
timeline.pruned = pruned.columns.flatMap((c) => c.cards).map((c) => ({ id: c.id, dependsOn: c.dependsOn || null }));

// ---- Descriptions (markdown.js) ----
const markdownCases = [
  '**bold** *it* _it_ __u__ ~~s~~ `code` ``a ` b`` ||spoil||',
  '***both*** __*ui*__ ~~**x**~~ ||*hid*||',
  'snake_case_name and 2*3*4, a * b * c, _not_italic_ here',
  '\\*not\\* **a *b* c** \\# \\> x',
  'see https://x.com/a_(b). and <https://y.com> or [site](https://z.com/p?q=1) [bad](javascript:alert(1)) http:// nothing',
  '**https://bold.link** [**strong** words](https://a.b/c) [a [b](https://c.d)',
  '# Head\n## Two\n### Three\n#nottag\n#### four\n-# small\n-#not',
  '> quote **b**\n> more\n>\n> after gap\nafter',
  '>>> all\nof this\n# even this',
  '- a\n* b\n  - nested\n      - deep\n1. one\n10. ten\n-not a list',
  '```js\nconst a = 1;\n\nconst b = 2;\n```\n```inline```\n```\nnever closed',
  'line1\nline2\n\n\npara2\r\nwindows',
  '**unclosed and *also ~~ and || and `',
  '<script>alert(1)</script> & "q" \'s\'',
  'Émile_ünïcode_ *ça* **日本語**',
  '',
  '   \n\n',
];
const markdown = markdownCases.map((src) => {
  const blocks = M.parse(src);
  return { src, blocks, snippet: M.snippetLines(blocks) };
});
// The toolbar, on a stand-in for the text box: what it leaves, and what it selects.
const box = (value, a, b) => ({
  value, selectionStart: a, selectionEnd: b,
  setRangeText(text, s, e, mode) { this.value = this.value.slice(0, s) + text + this.value.slice(e); if (mode === 'end') this.selectionStart = this.selectionEnd = s + text.length; },
  setSelectionRange(s, e) { this.selectionStart = s; this.selectionEnd = e; },
  focus() {}, dispatchEvent() {},
});
const formatted = [
  ['make this bold', 10, 14, 'bold'], ['', 0, 0, 'italic'], ['a b', 2, 3, 'strike'], ['x', 0, 1, 'code'], ['hide', 0, 4, 'spoiler'],
  ['u', 1, 1, 'underline'], ['go here', 3, 7, 'link'], ['', 0, 0, 'link'], ['https://a.b/c', 0, 13, 'link'],
  ['one\ntwo\nthree', 1, 6, 'list'], ['- one\n- two', 0, 11, 'list'], ['\nnext', 0, 0, 'list'], ['solo', 4, 4, 'list'],
].map(([value, a, b, kind]) => {
  const t = box(value, a, b);
  M.format(t, kind);
  return { value, a, b, kind, text: t.value, from: t.selectionStart, to: t.selectionEnd };
});

// ---- Sync ----
const raw = [
  { id: 'b1', name: '  Home  ', view: 'timeline', updatedAt: 5, columns: [
    { id: 'c1', name: ' To Do ', updatedAt: 2, cards: [
      card('k1', '', { priority: 'urgent', due: '2026-1-1', labels: [{ text: ' x ', color: '#ABCDEF' }, { text: '', color: '#000000' }, { text: 'bad', color: 'red' }], checklist: [{ text: 'a', done: 1 }, { text: ' ', done: true }], images: [{ id: 'i1', name: 'one' }, { id: 'bad id!' }], thumbnailId: 'nope', start: '2026-01-01', milestone: 'yes', completed: '2026-01-04', dependsOn: ['k2', 'k1', 'k2', 'no way'] }),
      card('k1', 'duplicate'),
      { title: 'no id' },
    ] },
    { id: 'c1', name: 'dup column', cards: [] },
    { id: 'c2', name: '   ', cards: [card('k2', 'Two', { updatedAt: -3, completed: 'yesterday' })] },
  ] },
  { id: 'b1', name: 'Duplicate board', columns: [] },
  { id: 'b2', name: '   ', columns: [] },
  { id: 'b3', name: 'Plain', columns: 'not a list' },
];
const dest = {
  id: 'm1', name: 'Mine', view: 'kanban', updatedAt: 100, columns: [
    { id: 'c1', name: 'To Do', updatedAt: 100, cards: [card('x1', 'Old copy', { updatedAt: 5 }), card('x2', 'Newer here', { updatedAt: 50 }), card('x3', 'Same', { updatedAt: 5 })] },
    { id: 'c2', name: 'Done', updatedAt: 1, cards: [card('x4', 'Moving', { updatedAt: 5 })] },
  ],
};
const src = {
  id: 'm1', name: 'Theirs', view: 'timeline', updatedAt: 200, columns: [
    { id: 'c1', name: 'To Do', updatedAt: 1, cards: [card('x1', 'New copy', { updatedAt: 9 }), card('x2', 'Older there', { updatedAt: 20 }), card('x3', 'Same', { updatedAt: 9 }), card('x4', 'Moving', { updatedAt: 9 })] },
    { id: 'c2', name: 'Finished', updatedAt: 2, cards: [] },
    { id: 'c3', name: 'New column', updatedAt: 3, cards: [card('x5', 'Brand new')] },
  ],
};
const merged = S.clone(dest);
const changes = S.mergeBoardInto(merged, S.clone(src));
const sync = {
  raw,
  cleaned: S.cleanBoards(raw),
  dest,
  src,
  merged,
  changes,
  wouldChangeSame: S.wouldChange([S.clone(merged)], S.clone(src)),
  wouldChangeNew: S.wouldChange([], S.clone(src)),
};

writeFileSync(join(here, '../test/fixtures/expected.json'), JSON.stringify({ timeline, sync, markdown, formatted }, null, 2) + '\n');
console.log('test/fixtures/expected.json written');
