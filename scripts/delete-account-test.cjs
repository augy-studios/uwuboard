// Delete Account (main-site/api/auth/delete-account.js): everything the account has goes, its
// card images and avatar too, or nothing does. Supabase, bcrypt and the session check are
// stand-ins here: nothing real is touched.
//
//   node scripts/delete-account-test.cjs
//
// What it checks:
//   1. A wrong password: 401, and nothing deleted.
//   2. The right one: every card image (more than a page of them) and both avatar files go from
//      the user's own folders, then the sessions, the boards and the account, in that order;
//      another user's files stay.
//   3. Storage failing: 500 saying nothing was deleted, and nothing was: rows and files as they
//      were.
//   4. A storage that answers but removes nothing: 500, not a loop that never ends.
const path = require('path');
const Module = require('module');

let fails = 0;
const ok = (name, cond, extra = '') => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ` :: ${extra}` : ''}`); if (!cond) fails++; };

const USER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';

// The stand-in Supabase: tables as lists of deletes, storage as a Map per bucket.
let files;
let deletes;
let storageFails;
let removeDoesNothing;
function reset() {
  files = { 'card-images': new Map(), avatars: new Map() };
  for (let i = 0; i < 250; i++) files['card-images'].set(`${USER}/img-${i}.jpg`, 1);
  files['card-images'].set(`${OTHER}/img-0.jpg`, 1);
  files.avatars.set(`${USER}/avatar.png`, 1);
  files.avatars.set(`${USER}/avatar.webp`, 1);
  files.avatars.set(`${OTHER}/avatar.png`, 1);
  deletes = [];
  storageFails = false;
  removeDoesNothing = false;
}
const supabase = {
  from(table) {
    return {
      select: () => ({ eq: () => ({ single: async () => ({ data: table === 'uwu_users' ? { password_hash: 'hash-of-right' } : null }) }) }),
      delete: () => ({ eq: async (col, val) => { deletes.push(`${table}:${col}=${val}`); return { error: null }; } }),
    };
  },
  storage: {
    from(bucket) {
      return {
        async list(prefix, { limit }) {
          if (storageFails) return { data: null, error: new Error('storage is down') };
          const names = [...files[bucket].keys()].filter((k) => k.startsWith(`${prefix}/`)).map((k) => k.slice(prefix.length + 1));
          // A folder entry as Supabase lists one: no id.
          return { data: [{ name: 'a-folder', id: null }, ...names.slice(0, limit).map((name) => ({ name, id: `id-${name}` }))], error: null };
        },
        async remove(keys) {
          if (removeDoesNothing) return { data: [], error: null };
          const removed = keys.filter((k) => files[bucket].delete(k)).map((name) => ({ name }));
          return { data: removed, error: null };
        },
      };
    },
  },
};

// The function's requires, answered with the stand-ins.
const api = path.join(__dirname, '../main-site/api');
const load = Module._load;
Module._load = function (request, parent, ...rest) {
  if (request === 'bcryptjs') return { compare: async (pw, hash) => hash === `hash-of-${pw}` };
  if (parent && parent.filename.startsWith(api)) {
    const target = path.resolve(path.dirname(parent.filename), request);
    if (target === path.join(api, 'lib/supabase')) return supabase;
    if (target === path.join(api, 'lib/auth')) return { requireAuth: async () => ({ userId: USER }) };
  }
  return load.call(this, request, parent, ...rest);
};
const handler = require(path.join(api, 'auth/delete-account.js'));

function call(body) {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200, payload: null,
      status(c) { this.statusCode = c; return this; },
      json(d) { this.payload = d; resolve(this); return this; },
    };
    handler({ method: 'DELETE', body, headers: {} }, res);
  });
}
const mine = (bucket) => [...files[bucket].keys()].filter((k) => k.startsWith(`${USER}/`)).length;
const theirs = (bucket) => [...files[bucket].keys()].filter((k) => k.startsWith(`${OTHER}/`)).length;

(async () => {
  const quiet = console.error;
  console.error = () => {};

  reset();
  let r = await call({ password: 'wrong' });
  ok('1. wrong password: 401', r.statusCode === 401);
  ok('1. nothing deleted', deletes.length === 0 && mine('card-images') === 250 && mine('avatars') === 2);

  reset();
  r = await call({ password: 'right' });
  ok('2. right password: 200', r.statusCode === 200, JSON.stringify(r.payload));
  ok('2. all 250 card images gone, over several pages', mine('card-images') === 0, String(mine('card-images')));
  ok('2. both avatar files gone', mine('avatars') === 0, String(mine('avatars')));
  ok('2. another user\'s files stay', theirs('card-images') === 1 && theirs('avatars') === 1);
  ok('2. then sessions, boards and the account, in that order', deletes.join() === [`uwu_sessions:user_id=${USER}`, `uwuboard_boards:user_id=${USER}`, `uwu_users:id=${USER}`].join(), deletes.join());

  reset();
  storageFails = true;
  r = await call({ password: 'right' });
  ok('3. storage failing: 500 saying nothing was deleted', r.statusCode === 500 && /nothing was deleted/.test(r.payload?.error), JSON.stringify(r.payload));
  ok('3. and nothing was', deletes.length === 0 && mine('card-images') === 250 && mine('avatars') === 2);

  reset();
  removeDoesNothing = true;
  r = await call({ password: 'right' });
  ok('4. removing nothing: 500, and it ends', r.statusCode === 500 && deletes.length === 0);

  console.error = quiet;
  console.log(fails ? `${fails} failed` : 'all passed');
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
