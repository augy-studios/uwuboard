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
// Prints PASS or FAIL for one check (with `extra` to explain it, if given) and counts the failures.
const ok = (name, condition, extra = '') => {
  let verdict;
  if (condition) {
    verdict = 'PASS';
  } else {
    verdict = 'FAIL';
  }
  let extraText = '';
  if (extra) {
    extraText = ` :: ${extra}`;
  }
  console.log(`${verdict} ${name}${extraText}`);
  if (!condition) {
    fails = fails + 1;
  }
};

const USER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';

// The stand-in Supabase: tables as lists of deletes, storage as a Map per bucket.
let files;
let deletes;
let storageFails;
let removeDoesNothing;
// Back to the start: 250 card images and two avatar files for the user, one of each for another.
function reset() {
  files = { 'card-images': new Map(), avatars: new Map() };
  for (let imageNumber = 0; imageNumber < 250; imageNumber = imageNumber + 1) {
    files['card-images'].set(`${USER}/img-${imageNumber}.jpg`, 1);
  }
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
      // select(...).eq(...).single(): the user, whose password is "right".
      select: () => {
        return {
          eq: () => {
            return {
              single: async () => {
                let user;
                if (table === 'uwu_users') {
                  user = { password_hash: 'hash-of-right' };
                } else {
                  user = null;
                }
                return { data: user };
              },
            };
          },
        };
      },
      // delete().eq(column, value): kept in `deletes`, in order.
      delete: () => {
        return {
          eq: async (column, value) => {
            deletes.push(`${table}:${column}=${value}`);
            return { error: null };
          },
        };
      },
    };
  },
  storage: {
    from(bucket) {
      return {
        async list(prefix, { limit }) {
          if (storageFails) {
            return { data: null, error: new Error('storage is down') };
          }
          const names = [...files[bucket].keys()]
            .filter((key) => {
              return key.startsWith(`${prefix}/`);
            })
            .map((key) => {
              return key.slice(prefix.length + 1);
            });
          const listedFiles = names.slice(0, limit).map((name) => {
            return { name, id: `id-${name}` };
          });
          // A folder entry as Supabase lists one: no id.
          return { data: [{ name: 'a-folder', id: null }, ...listedFiles], error: null };
        },
        async remove(keys) {
          if (removeDoesNothing) {
            return { data: [], error: null };
          }
          const removed = keys
            .filter((key) => {
              return files[bucket].delete(key);
            })
            .map((name) => {
              return { name };
            });
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
  if (request === 'bcryptjs') {
    // A password matches the hash "hash-of-<password>".
    return {
      compare: async (password, hash) => {
        return hash === `hash-of-${password}`;
      },
    };
  }
  if (parent && parent.filename.startsWith(api)) {
    const target = path.resolve(path.dirname(parent.filename), request);
    if (target === path.join(api, 'lib/supabase')) {
      return supabase;
    }
    if (target === path.join(api, 'lib/auth')) {
      return {
        requireAuth: async () => {
          return { userId: USER };
        },
      };
    }
  }
  return load.call(this, request, parent, ...rest);
};
const handler = require(path.join(api, 'auth/delete-account.js'));

// A DELETE with this body, answered once the function sends its JSON.
function call(body) {
  return new Promise((resolve) => {
    const response = {
      statusCode: 200, payload: null,
      status(code) { this.statusCode = code; return this; },
      json(data) { this.payload = data; resolve(this); return this; },
    };
    handler({ method: 'DELETE', body, headers: {} }, response);
  });
}
// How many files in `bucket` are the user's own, and how many the other user's.
const mine = (bucket) => {
  return [...files[bucket].keys()].filter((key) => {
    return key.startsWith(`${USER}/`);
  }).length;
};
const theirs = (bucket) => {
  return [...files[bucket].keys()].filter((key) => {
    return key.startsWith(`${OTHER}/`);
  }).length;
};

(async () => {
  const quiet = console.error;
  console.error = () => {};

  reset();
  let response = await call({ password: 'wrong' });
  ok('1. wrong password: 401', response.statusCode === 401);
  ok('1. nothing deleted', deletes.length === 0 && mine('card-images') === 250 && mine('avatars') === 2);

  reset();
  response = await call({ password: 'right' });
  ok('2. right password: 200', response.statusCode === 200, JSON.stringify(response.payload));
  ok('2. all 250 card images gone, over several pages', mine('card-images') === 0, String(mine('card-images')));
  ok('2. both avatar files gone', mine('avatars') === 0, String(mine('avatars')));
  ok('2. another user\'s files stay', theirs('card-images') === 1 && theirs('avatars') === 1);
  ok('2. then sessions, boards and the account, in that order', deletes.join() === [`uwu_sessions:user_id=${USER}`, `uwuboard_boards:user_id=${USER}`, `uwu_users:id=${USER}`].join(), deletes.join());

  reset();
  storageFails = true;
  response = await call({ password: 'right' });
  let errorText;
  if (response.payload !== null && response.payload !== undefined) {
    errorText = response.payload.error;
  }
  ok('3. storage failing: 500 saying nothing was deleted', response.statusCode === 500 && /nothing was deleted/.test(errorText), JSON.stringify(response.payload));
  ok('3. and nothing was', deletes.length === 0 && mine('card-images') === 250 && mine('avatars') === 2);

  reset();
  removeDoesNothing = true;
  response = await call({ password: 'right' });
  ok('4. removing nothing: 500, and it ends', response.statusCode === 500 && deletes.length === 0);

  console.error = quiet;
  if (fails) {
    console.log(`${fails} failed`);
  } else {
    console.log('all passed');
  }
  if (fails) {
    process.exit(1);
  } else {
    process.exit(0);
  }
})().catch((error) => {
  console.error(error);
  process.exit(2);
});
