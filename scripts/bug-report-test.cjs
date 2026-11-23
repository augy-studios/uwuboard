// Report a bug: the edge tray's form (main-site/js/bug-report.js) and the function that sends
// it to Augy on Telegram (main-site/api/bug-report.js). Telegram and Redis are stand-ins here:
// nothing is sent, and no real token is used.
//
//   node scripts/bug-report-test.cjs
//
// The function is run as Vercel would run it, on made-up requests, with fetch answered here. The
// form needs Playwright (PLAYWRIGHT=<path>, or one require('playwright') finds) and Chromium where
// Playwright finds it, or CHROME=<path to Chrome>; its /api/bug-report is the same function.
// API_ONLY=1 skips the form.
//
// What it checks:
//   1. Not set up (no token or chat), it says so, 503, and sends nothing.
//   2. Only POST; only from the site's own page when a browser says where it's from.
//   3. Nothing said, or too much, is refused, and nothing is sent.
//   4. A report goes to the chat as a rich message (sendRichMessage): a heading, a table with
//      the app, device, page and contact, and what was typed escaped, so it reads as it was
//      (<b> and all), the token only in Telegram's address. A chat that won't take a rich
//      message gets it as plain text (sendMessage).
//   5. Two a minute from one IP; with Redis, six an hour from one IP, sixty from everyone.
//   6. The field only a bot fills in: told it went, nothing sent.
//   7. Telegram failing or slow is a 502 that says to try again, with no token in the logs.
//   9. Several chats: each gets it (a topic's ID too), one taking it is enough, all failing is
//      a 502, and what isn't a chat is left out.
//  10. Pictures: up to three images, uploaded with the rich message and shown in it, each a
//      tg://photo?id= block; where the rich message won't go, sent after the plain one and
//      replying to it, one as a photo and more as an album; four, a non-image or one too big
//      is refused, sending nothing; the pictures failing still leaves the report sent.
//  11. Each report has an ID, the day in Singapore and four letters, answered and in the message;
//      a whole-page screenshot (`full`) goes as a file too, replying to the report, and the
//      report counts as sent even if the file doesn't.
//   8. The form: the edge tray's Report a bug; it shows what it adds (never a board's or a
//      card's name), sends it, and says it's sent with its ID; not set up, it offers email
//      instead with the words filled in. Pictures: one from the device, and Screenshot a page,
//      which puts the form away, leaves a bar over the page (over a card's window too), takes
//      the page without the bar and comes back; a page bigger than the screen is taken whole,
//      marked `full`, and goes on as a file too.
const path = require('path');
const fs = require('fs');

const TOKEN = '123456:TEST-not-a-real-token';
const CHAT = '424242';
const REDIS = 'https://redis.test';
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

// `object[fieldName]`, or undefined when there is no object (null or undefined).
function fieldOrUndefined(object, fieldName) {
  if (object === null || object === undefined) {
    return undefined;
  }
  return object[fieldName];
}

// The value, or `fallback` when the value is missing or empty (any falsy value).
function valueOr(value, fallback) {
  if (!value) {
    return fallback;
  }
  return value;
}

// Telegram and Redis, as fetch sees them: every call kept in `sent`, Redis counted in `counts`.
const sent = [];
const counts = new Map();
let telegram = () => {
  return { status: 200, body: { ok: true, result: { message_id: 77 } } };
};
global.fetch = async (url, options = {}) => {
  url = String(url);
  if (url === REDIS) {
    const [command, key] = JSON.parse(options.body);
    if (command === 'INCR') {
      let currentCount = counts.get(key);
      if (!currentCount) {
        currentCount = 0;
      }
      counts.set(key, currentCount + 1);
    }
    let result;
    if (command === 'INCR') {
      result = counts.get(key);
    } else {
      result = 1;
    }
    return new Response(JSON.stringify({ result }), { status: 200 });
  }
  if (url.startsWith('https://api.telegram.org/')) {
    // A picture goes as a form: its files kept as what they are, not their bytes.
    let body;
    if (options.body instanceof FormData) {
      body = Object.fromEntries([...options.body.entries()].map(([fieldName, fieldValue]) => {
        if (typeof fieldValue === 'string') {
          return [fieldName, fieldValue];
        } else {
          return [fieldName, { file: true, size: fieldValue.size, type: fieldValue.type, name: fieldValue.name }];
        }
      }));
    } else {
      body = JSON.parse(options.body);
    }
    sent.push({ url, body });
    const answer = await telegram(options);
    return new Response(JSON.stringify(answer.body), { status: answer.status });
  }
  throw new Error(`unexpected fetch ${url}`);
};

// One call sent to Telegram: `sentCall.body[fieldName]`, or undefined when there was no such call.
function sentField(sentCall, fieldName) {
  if (sentCall === null || sentCall === undefined) {
    return undefined;
  }
  return sentCall.body[fieldName];
}

// Whether a call sent to Telegram went to an address ending in `ending`; undefined when there was
// no such call.
function urlEndsWith(sentCall, ending) {
  if (sentCall === null || sentCall === undefined) {
    return undefined;
  }
  return sentCall.url.endsWith(ending);
}

// The Bot API method of every call sent so far, e.g. "sendRichMessage,sendDocument".
function sentMethodNames() {
  return sent.map((sentCall) => {
    return sentCall.url.split('/').pop();
  }).join();
}

// A rich message's Markdown and media, from what was sent.
const rich = (sentCall) => {
  try {
    let richMessageJson;
    if (sentCall !== null && sentCall !== undefined) {
      richMessageJson = sentCall.body.rich_message;
    }
    return JSON.parse(richMessageJson);
  } catch {
    return null;
  }
};
// A rich message's Markdown, or '' when there isn't one.
const richMarkdownText = (sentCall) => {
  return valueOr(fieldOrUndefined(rich(sentCall), 'markdown'), '');
};
// Telegram refusing rich messages only: as an older Bot API or a chat that won't have them.
const noRich = (then) => {
  return (options) => {
    if (options.body instanceof FormData && options.body.has('rich_message')) {
      return { status: 400, body: { ok: false, description: 'Bad Request: rich messages are not allowed' } };
    } else {
      return then(options);
    }
  };
};

// A Vercel request and response, enough for the function. Each call comes from a new IP unless
// `ip` is given.
let ipSequence = 0;
function call(handler, { method = 'POST', body, headers = {}, ip } = {}) {
  let ipAddress = ip;
  if (ipAddress === undefined) {
    ipSequence = ipSequence + 1;
    ipAddress = `10.0.0.${ipSequence}`;
  }
  const request = { method, body, query: {}, headers: { host: 'uwuboard.test', 'x-real-ip': ipAddress, ...headers } };
  return new Promise((resolve) => {
    const response = {
      statusCode: 200, headers: {}, payload: null,
      setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
      status(code) { this.statusCode = code; return this; },
      json(data) { this.payload = data; resolve(this); return this; },
      end() { resolve(this); return this; },
    };
    Promise.resolve(handler(request, response)).catch((error) => {
      response.statusCode = 'threw';
      response.payload = String(error);
      resolve(response);
    });
  });
}

// One field of a response's JSON answer, or undefined when there was no answer.
function payloadField(response, fieldName) {
  return fieldOrUndefined(response.payload, fieldName);
}

const REPORT = {
  text: 'The <b>due date</b> on my card shows "Invalid" & never changes.\nSteps: open it, wait.',
  contact: '@someone',
  version: '1.0.1',
  platform: 'android',
  device: 'Android 14 · Chrome 130 · 412×915',
  page: 'Kanban board, card window',
};

// Checks 1–7 and 9–11: the function itself, on made-up requests. Returns it for the form's checks.
async function api() {
  // Redis on (it's read as the module loads), for the hour's limits.
  process.env.KV_REST_API_URL = REDIS;
  process.env.KV_REST_API_TOKEN = 'redis-test-token';
  const handler = require(path.join(__dirname, '../main-site/api/bug-report.js'));

  delete process.env.BUG_REPORT_BOT_TOKEN;
  delete process.env.BUG_REPORT_CHAT_ID;
  let response = await call(handler, { body: REPORT });
  ok('1. not set up: 503 with a message', response.statusCode === 503 && /can't be sent/.test(payloadField(response, 'error')), payloadField(response, 'error'));
  process.env.BUG_REPORT_BOT_TOKEN = TOKEN;
  response = await call(handler, { body: REPORT });
  ok('1. a token but no chat is still not set up', response.statusCode === 503);
  process.env.BUG_REPORT_CHAT_ID = CHAT;
  ok('1. nothing sent while not set up', sent.length === 0);

  response = await call(handler, { method: 'GET' });
  ok('2. GET refused', response.statusCode === 405 && response.headers.allow === 'POST');
  response = await call(handler, { body: REPORT, headers: { origin: 'https://evil.example' } });
  ok('2. another site\'s page refused', response.statusCode === 403);
  response = await call(handler, { body: REPORT, headers: { origin: 'not a url' } });
  ok('2. a nonsense Origin refused', response.statusCode === 403);

  for (const [label, body, code] of [
    ['no body', undefined, 400],
    ['no text', { ...REPORT, text: '' }, 400],
    ['only spaces', { ...REPORT, text: '   \n  ' }, 400],
    ['text not a string', { ...REPORT, text: ['a', 'b', 'c', 'd', 'e', 'f'] }, 400],
    ['over 2,000 characters', { ...REPORT, text: 'x'.repeat(2001) }, 400],
    ['over 8 KB in all', { ...REPORT, device: 'y'.repeat(9000) }, 413],
  ]) {
    response = await call(handler, { body });
    ok(`3. ${label}: ${code}`, response.statusCode === code, `${response.statusCode} ${valueOr(payloadField(response, 'error'), '')}`);
  }
  ok('3. nothing sent for any of them', sent.length === 0);

  response = await call(handler, { body: REPORT, headers: { origin: 'https://uwuboard.test' } });
  ok('4. a report from the site: 200', response.statusCode === 200, `${response.statusCode} ${JSON.stringify(response.payload)}`);
  const richCall = sent[0];
  const richCallUrl = fieldOrUndefined(richCall, 'url');
  ok('4. one call, to Telegram\'s sendRichMessage with the bot\'s token', sent.length === 1 && richCallUrl === `https://api.telegram.org/bot${TOKEN}/sendRichMessage`, richCallUrl);
  ok('4. to the chat set', sentField(richCall, 'chat_id') === CHAT);
  ok('4. no parse_mode', richCall && !('parse_mode' in richCall.body));
  const markdown = richMarkdownText(richCall);
  ok('4. answers the report\'s ID', /^\d{8}-[2-9A-HJKMNP-Z]{4}$/.test(valueOr(payloadField(response, 'id'), '')), JSON.stringify(response.payload));
  ok('4. the ID in the table too', markdown.includes(`| Report | ${payloadField(response, 'id')} |`), markdown.split('\n').slice(0, 8).join(' / '));
  ok('4. a heading with the report\'s ID, then the details as a table', /^# Bug report \d{8}-[2-9A-HJKMNP-Z]{4}\n/.test(markdown) && markdown.includes('| Detail | Given |\n| --- | --- |'), JSON.stringify(markdown));
  ok('4. the app and its version, the device, page and contact', markdown.includes('| App | Android app 1.0.1 |') && markdown.includes('| Device | Android 14 · Chrome 130 · 412×915 |') && markdown.includes('| Page | Kanban board, card window |') && !markdown.includes('Language') && markdown.includes('| Contact | @someone |'), JSON.stringify(markdown));
  ok('4. what was typed under its heading, escaped, a line a line', markdown.includes('## What went wrong\n\nThe \\<b\\>due date\\</b\\> on my card shows "Invalid" \\& never changes.  \nSteps: open it, wait.'), JSON.stringify(markdown));
  const richMessageOrEmpty = valueOr(rich(richCall), {});
  ok('4. no pictures, no media', !('media' in richMessageOrEmpty) && !/tg:\/\/photo/.test(markdown));
  ok('4. no token in the message', !markdown.includes(TOKEN));
  const { escapeMarkdown } = handler;
  ok('4. Markdown, HTML and Rich Markdown\'s own marks escaped', escapeMarkdown('*b* _i_ `c` [l](u) <u> ==m== ||s|| $x$ #h a|b \\') === '\\*b\\* \\_i\\_ \\`c\\` \\[l\\]\\(u\\) \\<u\\> \\=\\=m\\=\\= \\|\\|s\\|\\| \\$x\\$ \\#h a\\|b \\\\', escapeMarkdown('*b* _i_ `c` [l](u) <u> ==m== ||s|| $x$ #h a|b \\'));
  ok('4. a line that would be a list isn\'t', escapeMarkdown('- a\n+ b\n 2. c\n3) d\n-5 stays') === '\\- a\n\\+ b\n 2\\. c\n3\\) d\n-5 stays', JSON.stringify(escapeMarkdown('- a\n+ b\n 2. c\n3) d\n-5 stays')));
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, device: 'Pixel | Chrome' } });
  ok('4. a | in a table cell escaped', richMarkdownText(sent[0]).includes('| Device | Pixel \\| Chrome |'), richMarkdownText(sent[0]));

  // A chat that won't take a rich message: the plain text, as before.
  sent.length = 0;
  const logsRich = [];
  const consoleErrorBeforeRich = console.error;
  console.error = (...parts) => {
    logsRich.push(parts.join(' '));
  };
  telegram = noRich(() => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  });
  response = await call(handler, { body: REPORT });
  console.error = consoleErrorBeforeRich;
  const plainCall = sent[1];
  ok('4. no rich message: 200, then Telegram\'s sendMessage', response.statusCode === 200 && urlEndsWith(sent[0], '/sendRichMessage') && fieldOrUndefined(plainCall, 'url') === `https://api.telegram.org/bot${TOKEN}/sendMessage`, sent.map((sentCall) => {
    return sentCall.url;
  }).join());
  ok('4. the reason logged, never the token', logsRich.some((line) => {
    return line.includes('rich messages are not allowed') && line.includes('plain text');
  }) && !logsRich.some((line) => {
    return line.includes(TOKEN);
  }), logsRich.join(' | '));
  ok('4. to the chat set', sentField(plainCall, 'chat_id') === CHAT);
  ok('4. as plain text: no parse_mode', plainCall && !('parse_mode' in plainCall.body));
  ok('4. no link previews', fieldOrUndefined(sentField(plainCall, 'link_preview_options'), 'is_disabled') === true);
  const text = valueOr(sentField(plainCall, 'text'), '');
  ok('4. what was typed, as it was', text.includes(REPORT.text), JSON.stringify(text));
  ok('4. the app and its version', text.includes('App: Android app 1.0.1'));
  ok('4. the device, page and contact', text.includes(`Device: ${REPORT.device}`) && text.includes(`Page: ${REPORT.page}`) && text.includes('Contact: @someone'));
  ok('4. no token in the message', !text.includes(TOKEN));

  sent.length = 0;
  response = await call(handler, { body: { text: 'Only the words.\u0000\u0007 Bye' } });
  const onlyWordsText = sentField(sent[1], 'text');
  ok('4. with nothing else, it says so, control characters out', response.statusCode === 200 && /App: Unknown\n/.test(onlyWordsText) && /Contact: none given/.test(onlyWordsText) && /Only the words\. Bye$/.test(onlyWordsText), JSON.stringify(onlyWordsText));
  response = await call(handler, { body: { ...REPORT, platform: '<script>' } });
  ok('4. an unknown platform is Unknown', /App: Unknown 1\.0\.1/.test(sentField(sent.at(-1), 'text')));
  telegram = () => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  };

  // A minute's limit, from one IP.
  sent.length = 0;
  const codes = [];
  for (let attempt = 0; attempt < 3; attempt = attempt + 1) {
    codes.push((await call(handler, { body: REPORT, ip: '10.9.9.9' })).statusCode);
  }
  ok('5. two a minute from one IP, then 429', codes.join() === '200,200,429', codes.join());
  ok('5. the third not sent', sent.length === 2);
  // An hour's, from one IP (a different instance each minute, so only Redis counts).
  const hour = Math.floor(Date.now() / 3600000);
  counts.set(`uwuboard:bug:${hour}:10.8.8.8`, 6);
  response = await call(handler, { body: REPORT, ip: '10.8.8.8' });
  ok('5. a seventh in the hour from one IP: 429', response.statusCode === 429);
  counts.set(`uwuboard:bug:${hour}:all`, 60);
  response = await call(handler, { body: REPORT });
  ok('5. the sixty-first in the hour from anyone: 429', response.statusCode === 429);
  counts.clear();

  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, website: 'https://spam.example' } });
  ok('6. the bot\'s field filled in: 200, nothing sent', response.statusCode === 200 && sent.length === 0);

  const logs = [];
  const originalConsoleError = console.error;
  console.error = (...parts) => {
    logs.push(parts.join(' '));
  };
  telegram = () => {
    return { status: 400, body: { ok: false, description: 'Bad Request: chat not found' } };
  };
  response = await call(handler, { body: REPORT });
  ok('7. Telegram refusing it, rich and plain: 502, try again', response.statusCode === 502 && /try again/.test(payloadField(response, 'error')) && urlEndsWith(sent.at(-2), '/sendRichMessage') && urlEndsWith(sent.at(-1), '/sendMessage'));
  telegram = () => {
    throw Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' });
  };
  response = await call(handler, { body: REPORT });
  ok('7. Telegram too slow: 502', response.statusCode === 502);
  console.error = originalConsoleError;
  ok('7. the reason logged, never the token', logs.some((line) => {
    return line.includes('chat not found');
  }) && !logs.some((line) => {
    return line.includes(TOKEN);
  }), logs.join(' | '));
  telegram = () => {
    return { status: 200, body: { ok: true } };
  };

  // Several chats.
  const { chats } = handler;
  ok('9. read from commas, spaces and new lines', JSON.stringify(chats('424242, -1001234567890/17\n@uwuboard_reports  -4012345678')) === JSON.stringify([
    { chat_id: '424242' }, { chat_id: '-1001234567890', message_thread_id: 17 }, { chat_id: '@uwuboard_reports' }, { chat_id: '-4012345678' },
  ]), JSON.stringify(chats('424242, -1001234567890/17\n@uwuboard_reports  -4012345678')));
  ok('9. what isn\'t a chat is left out', JSON.stringify(chats('abc, 12a, @x, /5, , 42')) === JSON.stringify([{ chat_id: '42' }]), JSON.stringify(chats('abc, 12a, @x, /5, , 42')));
  process.env.BUG_REPORT_CHAT_ID = 'nonsense';
  response = await call(handler, { body: REPORT });
  ok('9. no chat that reads as one: not set up, 503', response.statusCode === 503);
  process.env.BUG_REPORT_CHAT_ID = `${CHAT}, -1001234567890/17, @uwuboard_reports`;
  sent.length = 0;
  response = await call(handler, { body: REPORT });
  ok('9. three chats: 200, three messages', response.statusCode === 200 && sent.length === 3, `${response.statusCode} ${sent.length}`);
  ok('9. each to its chat, the topic with its ID, the same words', sentField(sent[0], 'chat_id') === CHAT && !('message_thread_id' in sent[0].body)
    && sentField(sent[1], 'chat_id') === '-1001234567890' && sent[1].body.message_thread_id === '17'
    && sentField(sent[2], 'chat_id') === '@uwuboard_reports' && sent.every((sentCall) => {
      return sentCall.body.rich_message === sent[0].body.rich_message;
    }));
  logs.length = 0;
  console.error = (...parts) => {
    logs.push(parts.join(' '));
  };
  sent.length = 0;
  // Only the first chat takes it; the other two refuse.
  telegram = (options) => {
    let chatId;
    if (options.body instanceof FormData) {
      chatId = options.body.get('chat_id');
    } else {
      chatId = JSON.parse(options.body).chat_id;
    }
    if (chatId === CHAT) {
      return { status: 200, body: { ok: true } };
    } else {
      return { status: 403, body: { ok: false, description: 'Forbidden: bot is not a member of the channel chat' } };
    }
  };
  response = await call(handler, { body: REPORT });
  ok('9. one took it, two didn\'t: still 200', response.statusCode === 200);
  ok('9. the two that didn\'t are logged by place, with the reason', logs.some((line) => {
    return line.includes('chat 2:') && line.includes('not a member');
  }) && logs.some((line) => {
    return line.includes('chat 3:');
  }) && !logs.some((line) => {
    return line.includes(TOKEN);
  }), logs.join(' | '));
  ok('9. the one that took it got one message, the others a rich and a plain try each', sent.filter((sentCall) => {
    return sentCall.body.chat_id === CHAT;
  }).length === 1 && sent.filter((sentCall) => {
    return sentCall.body.chat_id !== CHAT;
  }).length === 4, sent.map((sentCall) => {
    return `${sentCall.body.chat_id}:${sentCall.url.split('/').pop()}`;
  }).join());
  telegram = () => {
    return { status: 400, body: { ok: false, description: 'Bad Request: chat not found' } };
  };
  response = await call(handler, { body: REPORT });
  ok('9. none took it: 502', response.statusCode === 502);
  console.error = originalConsoleError;
  telegram = () => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  };
  process.env.BUG_REPORT_CHAT_ID = CHAT;

  // 10. Pictures: in the rich message, uploaded with it.
  const jpeg = (kilobytes) => {
    return `data:image/jpeg;base64,${Buffer.alloc(kilobytes * 1024, 7).toString('base64')}`;
  };
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(50)] } });
  let richMessage = rich(sent[0]);
  ok('10. one picture: 200, one rich message, nothing after it', response.statusCode === 200 && sent.length === 1 && sent[0].url.endsWith('/sendRichMessage'), sent.map((sentCall) => {
    return sentCall.url;
  }).join());
  ok('10. the picture uploaded with it, as p0', fieldOrUndefined(sentField(sent[0], 'p0'), 'file') && sent[0].body.p0.type === 'image/jpeg' && JSON.stringify(fieldOrUndefined(richMessage, 'media')) === JSON.stringify([{ id: 'p0', media: { type: 'photo', media: 'attach://p0' } }]), JSON.stringify(fieldOrUndefined(richMessage, 'media')));
  ok('10. and shown in it, under Picture', /## Picture\n\n!\[\]\(tg:\/\/photo\?id=p0\)$/.test(valueOr(fieldOrUndefined(richMessage, 'markdown'), '')), JSON.stringify(fieldOrUndefined(richMessage, 'markdown')));
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(40), jpeg(40), `data:image/png;base64,${Buffer.alloc(2048, 1).toString('base64')}`] } });
  richMessage = rich(sent[0]);
  ok('10. three: one rich message, three files, three picture blocks with captions', response.statusCode === 200 && sent.length === 1 && fieldOrUndefined(fieldOrUndefined(richMessage, 'media'), 'length') === 3 && fieldOrUndefined(sent[0].body.p2, 'type') === 'image/png'
    && ['p0', 'p1', 'p2'].every((id, index) => {
      return richMessage.markdown.includes(`![](tg://photo?id=${id} "Picture ${index + 1} of 3")`);
    }) && richMessage.markdown.includes('## Pictures (3)'), JSON.stringify(richMessage));

  // Where a rich message won't go: after the plain message, replying to it.
  const quiet = console.error;
  console.error = () => {};
  telegram = noRich(() => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  });
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(50)] } });
  sent.shift();
  ok('10. one picture: 200', response.statusCode === 200, `${response.statusCode} ${JSON.stringify(response.payload)}`);
  ok('10. no rich: the message says there are pictures', /Pictures: 1, below/.test(valueOr(sentField(sent[0], 'text'), '')), sentField(sent[0], 'text'));
  ok('10. no rich: then sendPhoto, to the chat, replying to the message', urlEndsWith(sent[1], '/sendPhoto') && sent[1].body.chat_id === CHAT && JSON.parse(sent[1].body.reply_parameters).message_id === 77 && fieldOrUndefined(sent[1].body.photo, 'file') && sent[1].body.photo.type === 'image/jpeg', JSON.stringify(fieldOrUndefined(sent[1], 'body')));
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(40), jpeg(40), `data:image/png;base64,${Buffer.alloc(2048, 1).toString('base64')}`] } });
  sent.shift();
  const album = sent[1];
  ok('10. no rich: three as an album of three, the first with a caption', response.statusCode === 200 && urlEndsWith(album, '/sendMediaGroup') && JSON.parse(album.body.media).length === 3 && /3 pictures/.test(JSON.parse(album.body.media)[0].caption) && fieldOrUndefined(album.body.p2, 'type') === 'image/png', JSON.stringify(fieldOrUndefined(album, 'body')));
  console.error = quiet;
  telegram = () => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  };
  sent.length = 0;
  for (const [label, pictureList] of [['four', [jpeg(1), jpeg(1), jpeg(1), jpeg(1)]], ['not an image', ['data:text/html;base64,PGI+']], ['too big', [jpeg(1300)]], ['not a list', 'x']]) {
    response = await call(handler, { body: { ...REPORT, images: pictureList } });
    ok(`10. ${label}: 400`, response.statusCode === 400, `${response.statusCode} ${valueOr(payloadField(response, 'error'), '')}`);
  }
  ok('10. nothing sent for any of them', sent.length === 0);
  const consoleErrorBeforePictures = console.error;
  console.error = () => {};
  // Anything sent as a form (pictures, and the rich message with them) is refused.
  telegram = (options) => {
    if (options.body instanceof FormData) {
      return { status: 400, body: { ok: false, description: 'Bad Request: photo too big' } };
    } else {
      return { status: 200, body: { ok: true, result: { message_id: 78 } } };
    }
  };
  // (the rich message with the picture refused, then the plain one sent, its picture refused)
  response = await call(handler, { body: { ...REPORT, images: [jpeg(10)] } });
  ok('10. the pictures failing: the report still sent, 200', response.statusCode === 200);
  console.error = consoleErrorBeforePictures;
  // 11. Report IDs and whole-page screenshots.
  telegram = () => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  };
  const { reportId, fullShots } = handler;
  const fixedBytes = () => {
    return [0, 1, 2, 30];
  };
  ok('11. an ID is the day in Singapore and four letters', reportId(new Date('2026-11-02T17:30:00Z'), fixedBytes) === '20261103-234Z', reportId(new Date('2026-11-02T17:30:00Z'), fixedBytes));
  const ids = new Set(Array.from({ length: 200 }, () => {
    return reportId();
  }));
  ok('11. none of 0, O, 1, I or L, and 200 in a row all different', [...ids].every((id) => {
    return /^\d{8}-[2-9A-HJKMNP-Z]{4}$/.test(id);
  }) && ids.size === 200);
  ok('11. full: only whole numbers in range, once each', JSON.stringify(fullShots([2, 0, 0, 5, -1, 1.5, '1'], 3)) === '[0,2]' && JSON.stringify(fullShots('x', 3)) === '[]');
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(30), jpeg(40)], full: [1] } });
  const documentCall = sent.find((sentCall) => {
    return sentCall.url.endsWith('/sendDocument');
  });
  ok('11. a whole-page shot: the rich message, then it again as a file', response.statusCode === 200 && sent.length === 2 && sent[0].url.endsWith('/sendRichMessage') && documentCall === sent[1], sentMethodNames());
  ok('11. the file replies to the report, named and captioned with its ID', JSON.parse(valueOr(sentField(documentCall, 'reply_parameters'), '{}')).message_id === 77
    && fieldOrUndefined(sentField(documentCall, 'document'), 'name') === `report-${response.payload.id}-page-2.jpg` && documentCall.body.caption.includes(response.payload.id) && documentCall.body.document.size === 40 * 1024, JSON.stringify(fieldOrUndefined(documentCall, 'body')));
  ok('11. the photo in the rich message is still there, both pictures', fieldOrUndefined(fieldOrUndefined(rich(sent[0]), 'media'), 'length') === 2);
  console.error = () => {};
  telegram = noRich(() => {
    return { status: 200, body: { ok: true, result: { message_id: 91 } } };
  });
  sent.length = 0;
  response = await call(handler, { body: { ...REPORT, images: [jpeg(30)], full: [0] } });
  ok('11. no rich: message, photo, then the file, each with the ID', response.statusCode === 200 && sentMethodNames() === 'sendRichMessage,sendMessage,sendPhoto,sendDocument'
    && sent[1].body.text.startsWith(`Bug report ${response.payload.id},`) && sent[2].body.caption.includes(response.payload.id) && JSON.parse(sent[3].body.reply_parameters).message_id === 91, sentMethodNames());
  // Only the whole-page file is refused.
  telegram = (options) => {
    if (options.body instanceof FormData && options.body.has('document')) {
      return { status: 400, body: { ok: false, description: 'Bad Request: file too big' } };
    } else {
      return { status: 200, body: { ok: true, result: { message_id: 77 } } };
    }
  };
  response = await call(handler, { body: { ...REPORT, images: [jpeg(30)], full: [0] } });
  ok('11. the file failing: the report still sent, with its ID', response.statusCode === 200 && /^\d{8}-/.test(valueOr(payloadField(response, 'id'), '')));
  console.error = consoleErrorBeforePictures;
  telegram = () => {
    return { status: 200, body: { ok: true, result: { message_id: 77 } } };
  };
  return handler;
}

// Check 8: the site's form in a real (headless) browser, its /api/bug-report answered by the
// function itself and every other request served from main-site/ or refused.
async function form(handler) {
  let playwright;
  try {
    playwright = require(valueOr(process.env.PLAYWRIGHT, 'playwright'));
  } catch {
    try {
      playwright = require('playwright-core');
    } catch {
      playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright'));
    }
  }
  const SITE = path.resolve(valueOr(process.env.SITE, path.join(__dirname, '../main-site')));
  const ORIGIN = 'https://uwuboard.test';
  const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };
  const launchOptions = { headless: true };
  if (process.env.CHROME) {
    launchOptions.executablePath = process.env.CHROME;
  }
  const browser = await playwright.chromium.launch(launchOptions);
  const context = await browser.newContext({ viewport: { width: 400, height: 820 }, isMobile: true, hasTouch: true, serviceWorkers: 'block' });
  // A guest with one board, whose names must never be sent; no tours.
  await context.addInitScript(() => {
    if (sessionStorage.getItem('seeded')) {
      return;
    }
    sessionStorage.setItem('seeded', '1');
    localStorage.clear();
    localStorage.setItem('uwuboard.tour.welcome', 'done');
    localStorage.setItem('uwuboard.tour.pages', JSON.stringify(['kanban', 'timeline', 'newboard', 'card']));
    localStorage.setItem('kanbanflow_guest_boards', JSON.stringify([{
      id: 'b1', name: 'Secret Plans',
      columns: [{ id: 'c1', name: 'To Do', cards: [{ id: 'k1', title: 'Private card title', description: '', labels: [], checklist: [] }] }],
    }]));
  });
  const posted = [];
  await context.route(`${ORIGIN}/**`, async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === '/api/bug-report') {
      const body = JSON.parse(valueOr(request.postData(), 'null'));
      posted.push(body);
      let origin = await request.headerValue('origin');
      if (!origin) {
        origin = undefined;
      }
      const response = await call(handler, { method: request.method(), body, headers: { origin: origin } });
      let responseBody;
      if (response.payload) {
        responseBody = JSON.stringify(response.payload);
      } else {
        responseBody = '';
      }
      return route.fulfill({ status: response.statusCode, contentType: 'application/json', body: responseBody });
    }
    if (url.pathname.startsWith('/api/')) {
      return route.fulfill({ status: 404, contentType: 'application/json', body: '{}' });
    }
    let file;
    if (url.pathname === '/') {
      file = path.join(SITE, 'index.html');
    } else {
      file = path.join(SITE, decodeURIComponent(url.pathname));
    }
    if (!file.startsWith(SITE) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      return route.fulfill({ status: 404, body: '' });
    }
    return route.fulfill({ status: 200, contentType: valueOr(TYPES[path.extname(file)], 'application/octet-stream'), body: fs.readFileSync(file) });
  });
  await context.route(/^(?!https:\/\/uwuboard\.test\/)/, (route) => {
    return route.fulfill({ status: 404, body: '' });
  });
  const page = await context.newPage();
  const errors = [];
  page.on('console', (consoleMessage) => {
    if (process.env.DEBUG && consoleMessage.type() !== 'log') {
      console.log('console:', consoleMessage.text());
    }
  });
  page.on('pageerror', (error) => {
    errors.push(String(error.message));
  });
  await page.goto(`${ORIGIN}/`);
  await page.click('#tab-btn-guest, [data-tab="guest"]');
  await page.click('#guest-btn');
  await page.waitForFunction(() => {
    return window.BugReport && !document.getElementById('columns-container').classList.contains('hidden') && !document.getElementById('hudRight').hidden;
  });
  // Whether the element with this id is showing (has no `hidden` class).
  const shown = (elementId) => {
    return page.evaluate((idInPage) => {
      return !document.getElementById(idInPage).classList.contains('hidden');
    }, elementId);
  };

  await page.click('#bugBtn');
  await page.waitForFunction(() => {
    return !document.getElementById('bugModal').classList.contains('hidden');
  });
  ok('8. the edge tray\'s Report a bug opens the form', true);
  const details = await page.textContent('#bugDetails');
  ok('8. it shows what it adds: the app, the device and the page', /^Web\b/.test(details) && /Chrome \d+/.test(details) && /Kanban board/.test(details), details);
  ok('8. never the board\'s or a card\'s name', !/Secret Plans|Private card/.test(details), details);

  await page.click('#bugSend');
  ok('8. empty, it asks what went wrong, and sends nothing', /what went wrong/i.test(await page.textContent('#bugStatus')) && posted.length === 0);

  sent.length = 0;
  await page.fill('#bugText', 'The card is blank <i>here</i>.');
  await page.fill('#bugContact', 'me@example.com');
  await page.click('#bugSend');
  await page.waitForFunction(() => {
    return /Sent/.test(document.getElementById('bugStatus').textContent);
  });
  const postedBody = valueOr(posted.at(-1), {});
  ok('8. sends the words, the contact and what it showed', postedBody.text === 'The card is blank <i>here</i>.' && postedBody.contact === 'me@example.com' && postedBody.platform === 'web' && postedBody.page === 'Kanban board' && /Chrome/.test(postedBody.device), JSON.stringify(postedBody));
  ok('8. nothing more: no boards, cards or account', Object.keys(postedBody).sort().join() === 'contact,device,full,images,page,platform,text,version,website' && !JSON.stringify(postedBody).includes('Secret Plans'), Object.keys(postedBody).join());
  ok('8. no pictures unless added', Array.isArray(postedBody.images) && postedBody.images.length === 0);
  ok('8. it reached Telegram (the stand-in) as a rich message', sent.length === 1 && sent[0].url.endsWith('/sendRichMessage') && richMarkdownText(sent[0]).includes('The card is blank \\<i\\>here\\</i\\>.') && richMarkdownText(sent[0]).includes('*uwuBoard*'), richMarkdownText(sent[0]));
  ok('8. it says the report\'s ID once sent', /Sent as report \d{8}-[2-9A-HJKMNP-Z]{4}\./.test(await page.textContent('#bugStatus')), await page.textContent('#bugStatus'));
  ok('8. the form is cleared once sent', (await page.inputValue('#bugText')) === '' && (await page.inputValue('#bugContact')) === '');

  // Pictures: one from the device, and Screenshot a page of a card's window.
  sent.length = 0;
  await page.fill('#bugText', 'With pictures, please.');
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  await page.setInputFiles('#bugPicFile', { name: 'shot.png', mimeType: 'image/png', buffer: png });
  await page.waitForFunction(() => {
    return document.querySelectorAll('#bugShots .bugShot').length === 1;
  });
  ok('8. a picture from the device shows, with a way to take it off', await page.$('#bugShots .bugShotX') !== null);
  await page.click('#bugScreenshot');
  await page.waitForFunction(() => {
    return document.getElementById('bugModal').classList.contains('hidden');
  });
  ok('8. Screenshot a page puts the form away and shows the bar', !(await shown('bugModal')) && (await page.isVisible('#bugShotBar')));
  // Off to a card's window: the bar stays over it, and can be pressed.
  await page.click('.card');
  await page.waitForFunction(() => {
    return !document.getElementById('card-modal').classList.contains('hidden');
  });
  ok('8. the bar floats over a window', await page.evaluate(() => {
    // What's on top at the middle of the bar's button: the bar, not the window under it.
    const rectangle = document.getElementById('bugShotTake').getBoundingClientRect();
    const topElement = document.elementFromPoint(rectangle.x + rectangle.width / 2, rectangle.y + rectangle.height / 2);
    if (topElement === null || topElement === undefined) {
      return false;
    }
    const bar = topElement.closest('#bugShotBar');
    return bar !== null && bar !== undefined;
  }));
  await page.click('#bugShotTake');
  await page.waitForFunction(() => {
    return !document.getElementById('bugModal').classList.contains('hidden');
  }, null, { timeout: 20000 });
  ok('8. Screenshot this page adds the page and brings the form back, the bar gone', (await page.$$('#bugShots .bugShot')).length === 2 && !(await page.isVisible('#bugShotBar')), await page.textContent('#bugStatus'));
  ok('8. what was typed is still there', (await page.inputValue('#bugText')) === 'With pictures, please.');
  ok('8. the page it says is the card\'s window', /Kanban board, card window/.test(await page.textContent('#bugDetails')), await page.textContent('#bugDetails'));
  if (process.env.SHOTS) {
    const imageSource = await page.evaluate(() => {
      return document.querySelectorAll('#bugShots img')[1].src;
    });
    fs.writeFileSync(path.join(process.env.SHOTS, 'bug-card-window.jpg'), Buffer.from(imageSource.split(',')[1], 'base64'));
  }
  await page.click('#bugSend');
  await page.waitForFunction(() => {
    return /Sent/.test(document.getElementById('bugStatus').textContent);
  });
  const withPictures = valueOr(posted.at(-1), {});
  ok('8. both sent, as JPEGs', fieldOrUndefined(withPictures.images, 'length') === 2 && withPictures.images.every((image) => {
    return image.startsWith('data:image/jpeg;base64,');
  }), String(fieldOrUndefined(withPictures.images, 'length')));
  ok('8. and on to Telegram in the rich message, two pictures in it', sent.length === 1 && fieldOrUndefined(fieldOrUndefined(rich(sent[0]), 'media'), 'length') === 2 && fieldOrUndefined(sent[0].body.p1, 'file'), JSON.stringify(fieldOrUndefined(rich(sent[0]), 'media')));
  ok('8. the pictures cleared once sent', (await page.$$('#bugShots .bugShot')).length === 0);
  ok('8. a page no bigger than the screen: no file, nothing marked whole-page', JSON.stringify(withPictures.full) === '[]' && !sent.some((sentCall) => {
    return sentCall.url.endsWith('/sendDocument');
  }));
  await page.evaluate(() => {
    return window.closeModal('bugModal');
  });
  await page.keyboard.press('Escape');

  // Cancel: back to the form, nothing taken.
  await page.click('#bugBtn');
  await page.click('#bugScreenshot');
  await page.click('#bugShotCancel');
  ok('8. Cancel goes back to the form, nothing taken', (await shown('bugModal')) && !(await page.isVisible('#bugShotBar')) && (await page.$$('#bugShots .bugShot')).length === 0);

  // A page taller than the screen: the whole of it, top to bottom, and a file too.
  sent.length = 0;
  await page.evaluate(() => {
    const tall = document.createElement('div');
    tall.id = 'testTall';
    tall.style.cssText = 'position:relative;height:2400px;background:linear-gradient(#f00,#00f)';
    document.body.appendChild(tall);
    document.body.style.overflow = 'visible';
    document.body.style.height = 'auto';
  });
  const pageHeight = await page.evaluate(() => {
    return Math.max(document.scrollingElement.scrollHeight, document.body.scrollHeight);
  });
  await page.fill('#bugText', 'The whole page, please.');
  await page.click('#bugScreenshot');
  await page.click('#bugShotTake');
  await page.waitForFunction(() => {
    return document.querySelectorAll('#bugShots .bugShot').length === 1 || /Couldn't take/.test(document.getElementById('bugStatus').textContent);
  }, null, { timeout: 30000 });
  const shotSize = await page.evaluate(() => {
    const image = document.querySelector('#bugShots img');
    if (image) {
      return [image.naturalWidth, image.naturalHeight];
    } else {
      return null;
    }
  });
  ok('8. a tall page: the screenshot is the whole page, not the screen', Boolean(shotSize) && pageHeight > 820 * 2 && shotSize[1] / shotSize[0] > (pageHeight / 400) * 0.95, `${shotSize} for a page ${pageHeight} tall`);
  ok('8. within what Telegram takes as a photo', Boolean(shotSize) && shotSize[0] + shotSize[1] <= 10000 && shotSize[1] <= shotSize[0] * 20, String(shotSize));
  await page.click('#bugSend');
  await page.waitForFunction(() => {
    return /Sent/.test(document.getElementById('bugStatus').textContent);
  });
  const tallSent = valueOr(posted.at(-1), {});
  // The picture's length as a data URL; base64 is 4 characters for every 3 bytes, hence * 0.75.
  const tallImageLength = valueOr(fieldOrUndefined(fieldOrUndefined(tallSent.images, 0), 'length'), 0);
  ok('8. sent marked whole-page, under 900 KB', JSON.stringify(tallSent.full) === '[0]' && tallImageLength * 0.75 <= 900 * 1024 + 4, `${JSON.stringify(tallSent.full)} ${Math.round(tallImageLength * 0.75 / 1024)} KB`);
  ok('8. and on to Telegram as a photo and as a file', sent.length === 2 && sent[1].url.endsWith('/sendDocument'), sentMethodNames());
  await page.evaluate(() => {
    const tall = document.getElementById('testTall');
    if (tall !== null && tall !== undefined) {
      tall.remove();
    }
    document.body.style.overflow = '';
    document.body.style.height = '';
  });

  // Not set up: email instead, with the words in it.
  delete process.env.BUG_REPORT_CHAT_ID;
  await page.fill('#bugText', 'Second one, please read.');
  await page.click('#bugSend');
  await page.waitForFunction(() => {
    return /can't be sent/.test(document.getElementById('bugStatus').textContent);
  });
  const mail = await page.getAttribute('#bugStatus a', 'href');
  ok('8. not set up, it offers email instead', /^mailto:augy@augystudios\.com\?/.test(valueOr(mail, '')), mail);
  ok('8. the email has the words and what it adds', decodeURIComponent(valueOr(mail, '')).includes('Second one, please read.') && decodeURIComponent(valueOr(mail, '')).includes('Kanban board'));
  ok('8. the words stay in the box', (await page.inputValue('#bugText')) === 'Second one, please read.');
  process.env.BUG_REPORT_CHAT_ID = CHAT;
  if (process.env.SHOTS) {
    await page.screenshot({ path: path.join(process.env.SHOTS, 'bug-form.png') });
  }

  ok('8. no page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
}

(async () => {
  const handler = await api();
  if (!process.env.API_ONLY) {
    await form(handler);
  }
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
