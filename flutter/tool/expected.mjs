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
const ctx = { window: {}, document: { getElementById: () => null }, localStorage: { getItem: () => null, setItem() {} }, console };
vm.createContext(ctx);
vm.runInContext(readFileSync(join(site, 'timeline.js'), 'utf8'), ctx);
const T = ctx.window.Timeline;

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
];
const board = {
  id: 'b1', name: 'Plan', view: 'timeline', columns: [
    { id: 'p1', name: 'Design', cards: [spanCards[0], { ...spanCards[1], dependsOn: ['a'] }] },
    { id: 'p2', name: 'Build', cards: [{ ...spanCards[2], dependsOn: ['b'] }, spanCards[3], spanCards[4], spanCards[5]] },
  ],
};
const timeline = {
  spans: spanCards.map((c) => ({ id: c.id, span: T.span(c) })),
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

// ---- Sync ----
const raw = [
  { id: 'b1', name: '  Home  ', view: 'timeline', updatedAt: 5, columns: [
    { id: 'c1', name: ' To Do ', updatedAt: 2, cards: [
      card('k1', '', { priority: 'urgent', due: '2026-1-1', labels: [{ text: ' x ', color: '#ABCDEF' }, { text: '', color: '#000000' }, { text: 'bad', color: 'red' }], checklist: [{ text: 'a', done: 1 }, { text: ' ', done: true }], images: [{ id: 'i1', name: 'one' }, { id: 'bad id!' }], thumbnailId: 'nope', start: '2026-01-01', milestone: 'yes', dependsOn: ['k2', 'k1', 'k2', 'no way'] }),
      card('k1', 'duplicate'),
      { title: 'no id' },
    ] },
    { id: 'c1', name: 'dup column', cards: [] },
    { id: 'c2', name: '   ', cards: [card('k2', 'Two', { updatedAt: -3 })] },
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

writeFileSync(join(here, '../test/fixtures/expected.json'), JSON.stringify({ timeline, sync }, null, 2) + '\n');
console.log('test/fixtures/expected.json written');
