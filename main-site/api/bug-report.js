// POST /api/bug-report: Report a bug. The edge tray's form (js/bug-report.js) and the apps'
// (flutter/lib/features/bug/bug_report.dart) send what went wrong here, and it reaches Augy as a
// message from a Telegram bot.
//
//   POST { text, contact?, version?, platform?, device?, page?, website?, images?, full? }
//     → 200 { id }
//
// `images` (optional) is up to MAX_IMAGES pictures as JPEG, PNG or WebP data URLs, each at most
// MAX_IMAGE_BYTES (the form makes them JPEGs of about 900 KB at most). `full` (optional) lists
// which of them are whole-page screenshots: as tall (or as wide) as the page, which Telegram
// shrinks as a photo till it can't be read, so each also goes as a file (sendDocument), at its
// full size.
//
// Each report gets an ID, reportId(): the day in Singapore and four letters, "20261103-7K3Q", in
// the message's heading and answered to the form, which shows it, so a report can be talked
// about by it. Nothing's stored: the day keeps them in order, the letters apart.
//
// It goes as a Telegram rich message (Bot API sendRichMessage): a heading, a table of what the
// form added, what was typed under its own heading, and the pictures in the message itself,
// uploaded with it (InputRichMessage `media`, each a tg://photo?id= link in the Markdown). If a
// chat won't take a rich message, it gets the same words as plain text (sendMessage), then the
// pictures as a photo or an album replying to it.
//
// What's sent on is what the person typed (`text`, and `contact` if they gave one), with what
// the form adds and shows them first: the app's version, which app (web, installed web app,
// Android, desktop), the device as their browser or app describes it and the page they were on
// (the kind of page, never a board's or a card's name). Nothing else: not their account, their
// boards or anything in them, unless a picture they chose to add shows it.
//
//   BUG_REPORT_BOT_TOKEN  the bot that sends it (BotFather's token)
//   BUG_REPORT_CHAT_ID    the chats it's sent to, one or more, split by commas, spaces or new
//                         lines: a chat ID (a person, who must have started the bot first; a
//                         group or channel the bot's in), a public group or channel's @name, or
//                         <chat ID>/<topic ID> for one topic of a group with topics. README's
//                         "Report a bug" says how to find each
//
// Sent to every chat at once; it counts as sent if one of them took it, and a chat that didn't
// is logged by its place in the list, with Telegram's reason.
//
// Without either it answers 503, and the form offers email instead. A public endpoint, so it's
// kept small: at most MAX_TEXT characters and MAX_BODY bytes besides the pictures, PER_MINUTE a
// minute from one IP in this instance, and with Redis set up (api/lib/ratelimit.js), PER_HOUR an
// hour from one IP and ALL_PER_HOUR from everyone together. Everything typed is escaped
// (escapeMarkdown), so nothing in it is read as Telegram's Rich Markdown or HTML; the plain text
// fallback has no parse_mode. `website` is a field people never see: filled in, it's a bot,
// told it went and sent nothing.

const { randomBytes } = require('crypto');
const { rateLimited, redis, storeConfigured } = require('./lib/ratelimit');

const APP_NAME = 'uwuBoard';
const MAX_TEXT = 2000;
const MAX_CONTACT = 200;
const MAX_BODY = 8 * 1024;
const MAX_IMAGES = 3;
const MAX_IMAGE_BYTES = 1200 * 1024;
const IMAGE_DATA_URL_PATTERN = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/;
const PER_MINUTE = 2;
const PER_HOUR = 6;
const ALL_PER_HOUR = 60;
const TELEGRAM_TIMEOUT_MILLISECONDS = 10 * 1000;
const PLATFORMS = { web: 'Web', pwa: 'Web, installed', android: 'Android app', desktop: 'Desktop app' };
// A report ID's letters: no 0 or O, 1, I or L, so one read out or typed back can't be mistaken.
const ID_LETTERS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const ID_LENGTH = 4;

// "20261103-7K3Q": the day in Singapore it was sent, and ID_LENGTH random letters.
function reportId(now = new Date(), random = (count) => { return randomBytes(count); }) {
  const day = new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, '');
  const letters = [...random(ID_LENGTH)].map((byte) => {
    return ID_LETTERS[byte % ID_LETTERS.length];
  }).join('');
  return `${day}-${letters}`;
}

// The whole-page screenshots among `count` pictures, as their indexes: `full` as sent, each
// once and in range, anything else left out.
function fullShots(full, count) {
  if (!Array.isArray(full)) {
    return [];
  }
  const inRange = full.filter((index) => {
    return Number.isInteger(index) && index >= 0 && index < count;
  });
  return [...new Set(inRange)].sort((first, second) => {
    return first - second;
  });
}

// BUG_REPORT_CHAT_ID as [{ chat_id, message_thread_id? }], in order; anything that isn't a chat
// ID, an @name or a chat ID with a topic is left out.
function chats(value = process.env.BUG_REPORT_CHAT_ID) {
  let text = value;
  if (!text) {
    text = '';
  }
  return String(text)
    .split(/[\s,]+/)
    .map((entry) => {
      // A chat ID, maybe followed by /<topic ID>.
      const match = entry.match(/^(-?\d+)(?:\/(\d+))?$/);
      if (match) {
        if (match[2]) {
          return { chat_id: match[1], message_thread_id: Number(match[2]) };
        } else {
          return { chat_id: match[1] };
        }
      }
      // A public group or channel's @name.
      if (/^@[A-Za-z]\w{3,}$/.test(entry)) {
        return { chat_id: entry };
      } else {
        return null;
      }
    })
    .filter(Boolean);
}

const configured = () => {
  return Boolean(process.env.BUG_REPORT_BOT_TOKEN && chats().length);
};

// A string as given, trimmed and cut to `maximumLength`, with control characters other than new
// lines and tabs taken out. Anything that isn't a string is "".
function clean(value, maximumLength, { lines: keepLines = false } = {}) {
  if (typeof value !== 'string') {
    return '';
  }
  let controlCharacters;
  if (keepLines) {
    controlCharacters = /[\u0000-\u0008\u000b-\u001f\u007f]/g;
  } else {
    controlCharacters = /[\u0000-\u001f\u007f]/g;
  }
  const cleaned = value.replace(controlCharacters, '').trim();
  if (cleaned.length > maximumLength) {
    return cleaned.slice(0, maximumLength);
  } else {
    return cleaned;
  }
}

// The pictures sent, as [{ type, bytes }], or null if any isn't one (a bad data URL, too big,
// too many).
function images(list) {
  if (list === null || list === undefined) {
    return [];
  }
  if (!Array.isArray(list) || list.length > MAX_IMAGES) {
    return null;
  }
  const pictures = [];
  for (const item of list) {
    let match = null;
    if (typeof item === 'string') {
      match = IMAGE_DATA_URL_PATTERN.exec(item);
    }
    if (!match) {
      return null;
    }
    const bytes = Buffer.from(match[2], 'base64');
    if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) {
      return null;
    }
    pictures.push({ type: match[1], bytes });
  }
  return pictures;
}

// The file name ending for a picture's type: "jpg" for JPEG, the type itself otherwise.
const fileExtension = (type) => {
  if (type === 'jpeg') {
    return 'jpg';
  } else {
    return type;
  }
};
const pictureBlob = (picture) => {
  return new Blob([picture.bytes], { type: `image/${picture.type}` });
};

// A Bot API method called with a form (files go with it). Its answer's `result`, or throws with
// Telegram's reason: never the token, which is only in the address.
async function telegramForm(method, form, timeoutMilliseconds) {
  const response = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/${method}`, { method: 'POST', body: form, signal: AbortSignal.timeout(timeoutMilliseconds) });
  if (response.ok) {
    return response.json().then((answer) => {
      if (answer === null || answer === undefined) {
        return null;
      }
      if (answer.result === null || answer.result === undefined) {
        return null;
      }
      return answer.result;
    }).catch(() => {
      return null;
    });
  }
  const reason = await response.json().then((answer) => {
    if (answer === null || answer === undefined) {
      return undefined;
    }
    return answer.description;
  }).catch(() => {
    return null;
  });
  let reasonText = '';
  if (reason) {
    reasonText = `: ${reason}`;
  }
  throw new Error(`Telegram replied ${response.status}${reasonText}`);
}

// A form for one chat, replying to `replyTo` where it's known.
function chatForm(chat, replyTo) {
  const form = new FormData();
  for (const [key, value] of Object.entries(chat)) {
    form.append(key, String(value));
  }
  if (replyTo) {
    form.append('reply_parameters', JSON.stringify({ message_id: replyTo, allow_sending_without_reply: true }));
  }
  return form;
}

// The pictures to one chat, replying to the report (`replyTo`): one as a photo, more as an album.
async function sendImages(chat, pictures, replyTo, id) {
  const form = chatForm(chat, replyTo);
  let picturesText;
  if (pictures.length === 1) {
    picturesText = 'Picture';
  } else {
    picturesText = `${pictures.length} pictures`;
  }
  const caption = `${picturesText} for report ${id}`;
  if (pictures.length === 1) {
    form.append('photo', pictureBlob(pictures[0]), `picture.${fileExtension(pictures[0].type)}`);
    form.append('caption', caption);
    return telegramForm('sendPhoto', form, TELEGRAM_TIMEOUT_MILLISECONDS * 2);
  }
  pictures.forEach((picture, index) => {
    form.append(`p${index}`, pictureBlob(picture), `picture${index + 1}.${fileExtension(picture.type)}`);
  });
  // The album: each picture by its file's name in the form, the caption on the first.
  const album = pictures.map((picture, index) => {
    const albumEntry = { type: 'photo', media: `attach://p${index}` };
    if (index === 0) {
      albumEntry.caption = caption;
    }
    return albumEntry;
  });
  form.append('media', JSON.stringify(album));
  return telegramForm('sendMediaGroup', form, TELEGRAM_TIMEOUT_MILLISECONDS * 2);
}

// A whole-page screenshot (`full`), as a file, so Telegram keeps it at its full size: replying to
// the report where it's known, captioned with the report's ID.
async function sendFile(chat, picture, pictureNumber, id, replyTo) {
  const form = chatForm(chat, replyTo);
  form.append('document', pictureBlob(picture), `report-${id}-page-${pictureNumber}.${fileExtension(picture.type)}`);
  form.append('caption', `Whole page, picture ${pictureNumber}, at full size: report ${id}`);
  form.append('disable_content_type_detection', 'true');
  return telegramForm('sendDocument', form, TELEGRAM_TIMEOUT_MILLISECONDS * 2);
}

// What the form added, as [label, value], in order: the report's ID first.
function details(body) {
  let platform = PLATFORMS[body.platform];
  if (!platform) {
    platform = 'Unknown';
  }
  const version = clean(body.version, 60);
  const rows = [];
  if (body.id) {
    rows.push(['Report', body.id]);
  }
  let versionText = '';
  if (version) {
    versionText = ` ${version}`;
  }
  rows.push(['App', `${platform}${versionText}`]);
  let device = clean(body.device, 200);
  if (!device) {
    device = 'not given';
  }
  rows.push(['Device', device]);
  let page = clean(body.page, 100);
  if (!page) {
    page = 'not given';
  }
  rows.push(['Page', page]);
  let contact = clean(body.contact, MAX_CONTACT);
  if (!contact) {
    contact = 'none given';
  }
  rows.push(['Contact', contact]);
  return rows;
}

// The message Augy gets as plain text, where a rich message won't go: what the form added,
// then what was typed.
function message(body) {
  let idText = '';
  if (body.id) {
    idText = ` ${body.id}`;
  }
  let picturesLines = [];
  if (Array.isArray(body.images) && body.images.length) {
    picturesLines = [`Pictures: ${body.images.length}, below`];
  }
  const lines = [
    `Bug report${idText}, ${APP_NAME}`,
    '',
    ...details(body).map(([label, value]) => {
      return `${label}: ${value}`;
    }),
    ...picturesLines,
    '',
    clean(body.text, MAX_TEXT, { lines: true }),
  ];
  return lines.join('\n');
}

// Text for Telegram's Rich Markdown, read as it is: Markdown's and HTML's characters, and the
// ones its own syntax uses (== marked, || spoiler, $ formulas), each behind a backslash, and a
// line that would start a list or a heading made not to.
const MARKDOWN_SPECIAL_CHARACTERS = /([\\*_~`|\[\]#>=<!$&^(){}])/g;
function escapeMarkdown(text) {
  return String(text)
    .replace(MARKDOWN_SPECIAL_CHARACTERS, '\\$1')
    .replace(/^(\s*)([-+])(?=\s|$)/gm, '$1\\$2')
    .replace(/^(\s*\d+)([.)])/gm, '$1\\$2');
}
// A table cell: escaped, on one line.
const escapeCell = (text) => {
  return escapeMarkdown(String(text).replace(/\s*\n\s*/g, ' '));
};

// The rich message: a heading, the form's details as a table, what was typed under a heading of
// its own (each line kept a line), then each picture as a block of its own, `p0`, `p1`... the
// ids of the files uploaded with it.
function richMarkdown(body, pictureCount = 0) {
  const typed = clean(body.text, MAX_TEXT, { lines: true }).split('\n').map((line) => {
    return escapeMarkdown(line);
  });
  let headingId = '';
  if (body.id) {
    headingId = ` ${escapeMarkdown(body.id)}`;
  }
  const lines = [
    `# Bug report${headingId}`,
    `*${APP_NAME}*`,
    '',
    '| Detail | Given |',
    '| --- | --- |',
    ...details(body).map(([label, value]) => {
      return `| ${label} | ${escapeCell(value)} |`;
    }),
    '',
    '## What went wrong',
    '',
    // Two spaces at a line's end keep the next on a line of its own; a blank line stays one.
    ...typed.map((line, index) => {
      if (index < typed.length - 1 && line && typed[index + 1]) {
        return `${line}  `;
      } else {
        return line;
      }
    }),
  ];
  if (pictureCount) {
    let picturesHeading;
    if (pictureCount === 1) {
      picturesHeading = 'Picture';
    } else {
      picturesHeading = `Pictures (${pictureCount})`;
    }
    lines.push('', `## ${picturesHeading}`);
    for (let index = 0; index < pictureCount; index = index + 1) {
      // With more than one, each picture is titled with its place among them.
      let pictureTitle = '';
      if (pictureCount > 1) {
        pictureTitle = ` "Picture ${index + 1} of ${pictureCount}"`;
      }
      lines.push('', `![](tg://photo?id=p${index}${pictureTitle})`);
    }
  }
  return lines.join('\n');
}

// The report as a rich message to one chat, its pictures in it: a form, so the files go with it.
// Its message's ID, for the whole-page files to reply to, or null if Telegram didn't say.
async function sendRich(chat, body, pictures) {
  const form = chatForm(chat);
  const richMessage = {
    markdown: richMarkdown(body, pictures.length),
  };
  if (pictures.length) {
    richMessage.media = pictures.map((picture, index) => {
      return { id: `p${index}`, media: { type: 'photo', media: `attach://p${index}` } };
    });
  }
  form.append('rich_message', JSON.stringify(richMessage));
  pictures.forEach((picture, index) => {
    form.append(`p${index}`, pictureBlob(picture), `picture${index + 1}.${fileExtension(picture.type)}`);
  });
  // Pictures take longer to upload, so they get twice the time.
  let timeoutMultiplier;
  if (pictures.length) {
    timeoutMultiplier = 2;
  } else {
    timeoutMultiplier = 1;
  }
  const result = await telegramForm('sendRichMessage', form, TELEGRAM_TIMEOUT_MILLISECONDS * timeoutMultiplier);
  if (result === null || result === undefined) {
    return null;
  }
  if (result.message_id === null || result.message_id === undefined) {
    return null;
  }
  return result.message_id;
}

// Over the hour's limit, from Redis: one IP's, or everyone's. A Redis that fails lets it through.
async function overHour(ipAddress) {
  if (!storeConfigured()) {
    return false;
  }
  try {
    const hour = Math.floor(Date.now() / 3600000);
    // Adds one to the key's count, which Redis forgets an hour after the first.
    const count = async (key) => {
      const newCount = await redis('INCR', key);
      if (newCount === 1) {
        await redis('EXPIRE', key, 3600);
      }
      return newCount;
    };
    if ((await count(`uwuboard:bug:${hour}:${ipAddress}`)) > PER_HOUR) {
      return true;
    }
    return (await count(`uwuboard:bug:${hour}:all`)) > ALL_PER_HOUR;
  } catch {
    return false; // the limit's a nicety
  }
}

// Why sending failed, for the log.
const why = (error) => {
  if (error.name === 'TimeoutError') {
    return 'Telegram took too long';
  } else {
    return error.message;
  }
};

// The endpoint: checks the request (where it's from, what's in it, how many came lately), then
// sends the report to every chat and answers with its ID once at least one chat took it.
async function handler(request, response) {
  response.setHeader('Cache-Control', 'no-store');
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed' });
  }
  if (!configured()) {
    return response.status(503).json({ error: "Bug reports can't be sent from the app yet." });
  }

  // Only from the site's own page: a browser sends Origin with a cross-site POST. The apps
  // send none.
  const origin = request.headers.origin;
  if (origin) {
    let host = '';
    try {
      host = new URL(origin).host;
    } catch {
      /* not a URL: refused below */
    }
    if (host !== request.headers.host) {
      return response.status(403).json({ error: 'Not from this site.' });
    }
  }

  // What was sent: it must be a JSON object, with pictures that are pictures, not too long,
  // and some words about what went wrong.
  let body = null;
  if (request.body && typeof request.body === 'object') {
    body = request.body;
  }
  if (!body) {
    return response.status(400).json({ error: 'Nothing was sent.' });
  }
  const pictures = images(body.images);
  if (!pictures) {
    return response.status(400).json({ error: `Pictures must be images, at most ${MAX_IMAGES}, each under ${Math.round(MAX_IMAGE_BYTES / 1024 / 1024 * 10) / 10} MB.` });
  }
  if (JSON.stringify({ ...body, images: undefined }).length > MAX_BODY) {
    return response.status(413).json({ error: "That's too long to send." });
  }
  if (typeof body.text !== 'string' || clean(body.text, MAX_TEXT + 1, { lines: true }).length < 5) {
    return response.status(400).json({ error: 'Please say what went wrong.' });
  }
  if (body.text.trim().length > MAX_TEXT) {
    return response.status(400).json({ error: `Please keep it under ${MAX_TEXT} characters.` });
  }

  // Who sent it, for the limits: Vercel's own header, else the first address forwarded.
  let ipAddress = request.headers['x-real-ip'];
  if (!ipAddress) {
    let forwardedFor = request.headers['x-forwarded-for'];
    if (!forwardedFor) {
      forwardedFor = '';
    }
    ipAddress = String(forwardedFor).split(',')[0].trim();
    if (!ipAddress) {
      ipAddress = 'unknown';
    }
  }
  if (await rateLimited(`bug:${ipAddress}`, PER_MINUTE)) {
    return response.status(429).json({ error: "That's a lot of reports at once. Try again in a minute." });
  }
  // The bot's field: no message, and no sign it was noticed.
  if (body.website) {
    return response.status(200).json({ id: reportId() });
  }
  if (await overHour(ipAddress)) {
    return response.status(429).json({ error: "That's a lot of reports this hour. Try again later." });
  }

  // To every chat at once, as a rich message, or as plain text where that won't go. One that
  // took it is enough; the others are logged.
  const id = reportId();
  const report = { ...body, id };
  const wholePageIndexes = fullShots(body.full, pictures.length);
  // Each whole-page screenshot as a file too, after the report; the report counts as sent even
  // if they don't go.
  const sendWholePageFiles = async (chat, chatIndex, replyTo) => {
    for (const pictureIndex of wholePageIndexes) {
      await sendFile(chat, pictures[pictureIndex], pictureIndex + 1, id, replyTo).catch((error) => {
        console.error(`bug-report: chat ${chatIndex + 1}: whole page ${pictureIndex + 1}: ${why(error)}`);
      });
    }
  };
  const plainText = message(report);
  const results = await Promise.all(chats().map(async (chat, chatIndex) => {
    try {
      const sentMessageId = await sendRich(chat, report, pictures);
      await sendWholePageFiles(chat, chatIndex, sentMessageId);
      return true;
    } catch (error) {
      console.error(`bug-report: chat ${chatIndex + 1}: rich message: ${why(error)}; sending it as plain text`);
    }
    // The rich message didn't go: the same words as plain text instead.
    try {
      const telegramResponse = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...chat, text: plainText, link_preview_options: { is_disabled: true } }),
        signal: AbortSignal.timeout(TELEGRAM_TIMEOUT_MILLISECONDS),
      });
      if (telegramResponse.ok) {
        // Then its pictures, replying to it. The report counts as sent even if they don't go.
        const replyTo = await telegramResponse.json().then((answer) => {
          if (answer === null || answer === undefined) {
            return undefined;
          }
          if (answer.result === null || answer.result === undefined) {
            return undefined;
          }
          return answer.result.message_id;
        }).catch(() => {
          return null;
        });
        if (pictures.length) {
          await sendImages(chat, pictures, replyTo, id).catch((error) => {
            console.error(`bug-report: chat ${chatIndex + 1}: pictures: ${why(error)}`);
          });
        }
        await sendWholePageFiles(chat, chatIndex, replyTo);
        return true;
      }
      const reason = await telegramResponse.json().then((answer) => {
        if (answer === null || answer === undefined) {
          return undefined;
        }
        return answer.description;
      }).catch(() => {
        return null;
      });
      let reasonText = '';
      if (reason) {
        reasonText = `: ${reason}`;
      }
      console.error(`bug-report: chat ${chatIndex + 1}: Telegram replied ${telegramResponse.status}${reasonText}`);
    } catch (error) {
      console.error(`bug-report: chat ${chatIndex + 1}: ${why(error)}`);
    }
    return false;
  }));
  if (!results.includes(true)) {
    return response.status(502).json({ error: "Couldn't send it right now. Please try again." });
  }
  return response.status(200).json({ id });
}

module.exports = handler;
// For scripts/bug-report-test.cjs.
Object.assign(module.exports, { reportId, fullShots, chats, configured, images, message, escapeMarkdown, richMarkdown });
