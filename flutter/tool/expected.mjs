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

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const siteScripts = join(toolDirectory, '../../main-site/js');

// timeline.js: its exported helpers, with the page it would touch stubbed out.
const timelineContext = {
  window: {},
  document: {
    getElementById: () => {
      return null;
    },
  },
  localStorage: {
    getItem: () => {
      return null;
    },
    setItem() {},
  },
  console,
};
vm.createContext(timelineContext);
vm.runInContext(readFileSync(join(siteScripts, 'timeline.js'), 'utf8'), timelineContext);
const Timeline = timelineContext.window.Timeline;

// sync.js keeps its helpers inside its closure: the pure ones are lifted out by name.
const syncSource = readFileSync(join(siteScripts, 'sync.js'), 'utf8');

// The source of `function name(...) { ... }` in sync.js, found by counting braces from the
// first `{` after the name until they balance again.
const functionSource = (name) => {
  const start = syncSource.indexOf(`function ${name}(`);
  if (start < 0) {
    throw new Error(`no function ${name} in sync.js`);
  }
  let depth = 0;
  for (let index = syncSource.indexOf('{', start); index < syncSource.length; index = index + 1) {
    if (syncSource[index] === '{') {
      depth = depth + 1;
    }
    if (syncSource[index] === '}') {
      depth = depth - 1;
      if (depth === 0) {
        return syncSource.slice(start, index + 1);
      }
    }
  }
  throw new Error(`unbalanced ${name}`);
};

// A `const name = …;`, however many lines it runs to: up to the first `;` outside any
// brackets.
const constSource = (name) => {
  const start = syncSource.indexOf(`const ${name} = `);
  if (start < 0) {
    throw new Error(`no const ${name} in sync.js`);
  }
  let depth = 0;
  for (let index = start; index < syncSource.length; index = index + 1) {
    const character = syncSource[index];
    if ('([{'.includes(character)) {
      depth = depth + 1;
    }
    if (')]}'.includes(character)) {
      depth = depth - 1;
    }
    if (character === ';' && depth === 0) {
      return syncSource.slice(start, index + 1);
    }
  }
  throw new Error(`unended ${name}`);
};

const liftedConstants = [
  'MAX_BOARDS', 'MAX_COLUMNS', 'MAX_CARDS', 'MAX_IMAGES', 'ID_PATTERN', 'isId', 'text', 'list', 'PRIORITIES', 'clone', 'stamp', 'cardSignature',
].map(constSource).join('\n');
const liftedFunctions = ['cleanCard', 'cleanBoards', 'mergeBoardInto', 'wouldChange'].map(functionSource).join('\n');
const lifted = liftedConstants + '\n' + liftedFunctions;
const syncHelpers = {};
vm.runInNewContext(`${lifted}\nexported.cleanBoards = cleanBoards; exported.mergeBoardInto = mergeBoardInto; exported.wouldChange = wouldChange; exported.clone = clone;`, { exported: syncHelpers, JSON });

// A card with every field at its empty value, plus whatever `extra` sets.
const card = (id, title, extra = {}) => {
  return { id, title, description: '', labels: [], checklist: [], due: '', priority: '', images: [], thumbnailId: null, updatedAt: 10, ...extra };
};

// All the cards on a board, column after column.
const allCards = (board) => {
  return board.columns.flatMap((column) => {
    return column.cards;
  });
};

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
  spans: spanCards.map((spanCard) => {
    return { id: spanCard.id, span: Timeline.span(spanCard) };
  }),
  clashes: [
    ['a', 'b'], ['b', 'c'], ['a', 'f'],
  ].map(([predecessorId, cardId]) => {
    const all = allCards(board);
    const predecessor = all.find((candidate) => {
      return candidate.id === predecessorId;
    });
    const waitingCard = all.find((candidate) => {
      return candidate.id === cardId;
    });
    return { pred: predecessorId, card: cardId, clash: Timeline.clashes(predecessor, waitingCard) };
  }),
  waitingOn: ['a', 'b', 'c'].map((id) => {
    return { id, waiting: [...Timeline.waitingOn(board, id)].sort() };
  }),
};
const pruned = syncHelpers.clone(board);
pruned.columns[0].cards.splice(0, 1);
Timeline.pruneDeps(pruned);
timeline.pruned = allCards(pruned).map((prunedCard) => {
  let dependsOn = prunedCard.dependsOn;
  if (!dependsOn) {
    dependsOn = null;
  }
  return { id: prunedCard.id, dependsOn };
});

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
const destinationBoard = {
  id: 'm1', name: 'Mine', view: 'kanban', updatedAt: 100, columns: [
    { id: 'c1', name: 'To Do', updatedAt: 100, cards: [card('x1', 'Old copy', { updatedAt: 5 }), card('x2', 'Newer here', { updatedAt: 50 }), card('x3', 'Same', { updatedAt: 5 })] },
    { id: 'c2', name: 'Done', updatedAt: 1, cards: [card('x4', 'Moving', { updatedAt: 5 })] },
  ],
};
const sourceBoard = {
  id: 'm1', name: 'Theirs', view: 'timeline', updatedAt: 200, columns: [
    { id: 'c1', name: 'To Do', updatedAt: 1, cards: [card('x1', 'New copy', { updatedAt: 9 }), card('x2', 'Older there', { updatedAt: 20 }), card('x3', 'Same', { updatedAt: 9 }), card('x4', 'Moving', { updatedAt: 9 })] },
    { id: 'c2', name: 'Finished', updatedAt: 2, cards: [] },
    { id: 'c3', name: 'New column', updatedAt: 3, cards: [card('x5', 'Brand new')] },
  ],
};
const merged = syncHelpers.clone(destinationBoard);
const changes = syncHelpers.mergeBoardInto(merged, syncHelpers.clone(sourceBoard));
const sync = {
  raw,
  cleaned: syncHelpers.cleanBoards(raw),
  dest: destinationBoard,
  src: sourceBoard,
  merged,
  changes,
  wouldChangeSame: syncHelpers.wouldChange([syncHelpers.clone(merged)], syncHelpers.clone(sourceBoard)),
  wouldChangeNew: syncHelpers.wouldChange([], syncHelpers.clone(sourceBoard)),
};

writeFileSync(join(toolDirectory, '../test/fixtures/expected.json'), JSON.stringify({ timeline, sync }, null, 2) + '\n');
console.log('test/fixtures/expected.json written');
