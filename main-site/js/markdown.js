'use strict';

/* A card's description, formatted the way Discord formats a message.

   Text:   **bold**  *italic* or _italic_  __underline__  ~~strikethrough~~  `code`  ||spoiler||
           and they nest: ***bold italic***, __*underlined italic*__.
   Lines:  # ## ### headings, -# small text, > quote (>>> quotes the rest), - or * bullets and
           1. numbers (two spaces in for each level), ``` code blocks ``` (a language after the
           first ``` is allowed and ignored).
   Links:  https:// addresses, <https://…>, and [words](https://…). Only http and https.
   A backslash shows the next symbol as it is: \*not italic\*.

   parse() turns the text into plain data (blocks of inline nodes) that toHtml() draws. The
   app's lib/data/markdown.dart is the same parser in Dart; flutter/tool/expected.mjs runs this
   one and test/parity_test.dart checks the two give the same answers. Nothing here touches
   the page until toHtml() is used, and every bit of text goes through esc(). */
(function () {
  const ESCAPABLE = '\\*_~|`[]()#>-.<';
  const MAX_DEPTH = 8;
  const isSpace = (c) => c === ' ' || c === '\t' || c === '\n';
  const isWord = (c) => !!c && /[\p{L}\p{N}]/u.test(c);
  const TRAILING = '.,!?;:\'"*_~|';

  /* ---- inline ---- */

  // Where `d` closes, searching from `from`: past escapes, never at `from` itself (no empty
  // runs), and for a doubled marker the last two of a longer run, so ***x*** is bold italic.
  function closeOf(s, d, from) {
    for (let k = from; k < s.length; k++) {
      if (s[k] === '\\') { k++; continue; }
      if (k > from && s.startsWith(d, k)) {
        while (d.length === 2 && s[k + 2] === d[0]) k++;
        return k;
      }
    }
    return -1;
  }

  // Where a single * or _ closes: not after a space, stepping over doubled markers (they're
  // the bold or underline inside it), and _ only at the end of a word, so snake_case stays.
  function italicClose(s, ch, from) {
    for (let k = from; k < s.length; k++) {
      if (s[k] === '\\') { k++; continue; }
      if (s[k] !== ch) continue;
      if (s[k + 1] === ch) { k++; continue; }
      if (k > from && !isSpace(s[k - 1]) && (ch === '*' || !isWord(s[k + 1]))) return k;
    }
    return -1;
  }

  // A bare address: trailing punctuation is the sentence's, and a ) only when unbalanced.
  function trimUrl(url) {
    for (;;) {
      const last = url[url.length - 1];
      if (TRAILING.includes(last)) url = url.slice(0, -1);
      else if (last === ')' && url.split('(').length < url.split(')').length) url = url.slice(0, -1);
      else return url;
    }
  }

  const PAIRS = [['||', 'spoiler'], ['**', 'b'], ['__', 'u'], ['~~', 's']];

  function inline(s, depth = 0, inLink = false) {
    const out = [];
    let buf = '';
    const push = (node) => {
      if (buf) { out.push({ t: 'text', v: buf }); buf = ''; }
      out.push(node);
    };
    let i = 0;
    outer: while (i < s.length) {
      const ch = s[i];
      if (ch === '\\' && i + 1 < s.length && ESCAPABLE.includes(s[i + 1])) { buf += s[i + 1]; i += 2; continue; }

      if (ch === '`') {
        const fence = s.startsWith('``', i) ? '``' : '`';
        const end = s.indexOf(fence, i + fence.length);
        if (end > i + fence.length) {
          push({ t: 'mono', v: s.slice(i + fence.length, end) });
          i = end + fence.length;
          continue;
        }
      }

      if (depth < MAX_DEPTH) {
        for (const [d, t] of PAIRS) {
          if (!s.startsWith(d, i)) continue;
          const end = closeOf(s, d, i + d.length);
          if (end !== -1) {
            push({ t, c: inline(s.slice(i + d.length, end), depth + 1, inLink) });
            i = end + d.length;
            continue outer;
          }
        }
        if ((ch === '*' || ch === '_') && s[i + 1] && !isSpace(s[i + 1]) && (ch === '*' || !isWord(s[i - 1]))) {
          const end = italicClose(s, ch, i + 1);
          if (end !== -1) {
            push({ t: 'i', c: inline(s.slice(i + 1, end), depth + 1, inLink) });
            i = end + 1;
            continue;
          }
        }
      }

      if (!inLink) {
        if (ch === '[') {
          const mid = s.indexOf('](', i + 1);
          if (mid > i + 1) {
            const m = s.slice(mid + 2).match(/^(https?:\/\/[^\s)]+)\)/);
            if (m) {
              push({ t: 'link', href: m[1], c: inline(s.slice(i + 1, mid), depth + 1, true) });
              i = mid + 2 + m[0].length;
              continue;
            }
          }
        }
        if (ch === '<') {
          const m = s.slice(i).match(/^<(https?:\/\/[^\s>]+)>/);
          if (m) {
            push({ t: 'link', href: m[1], c: [{ t: 'text', v: m[1] }] });
            i += m[0].length;
            continue;
          }
        }
        if (ch === 'h' && !isWord(s[i - 1])) {
          const m = s.slice(i).match(/^https?:\/\/[^\s<]+/);
          if (m) {
            const url = trimUrl(m[0]);
            if (url.length > url.indexOf('//') + 2) {
              push({ t: 'link', href: url, c: [{ t: 'text', v: url }] });
              i += url.length;
              continue;
            }
          }
        }
      }

      buf += ch;
      i++;
    }
    if (buf) out.push({ t: 'text', v: buf });
    return out;
  }

  /* ---- blocks ---- */

  const QUOTE = /^> |^>$/;

  function parse(src, inQuote = false) {
    const lines = String(src ?? '').replace(/\r\n?/g, '\n').split('\n');
    const blocks = [];
    let open = null; // the paragraph or list the next line can join
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let m;

      if ((m = line.match(/^\s*```(.*)$/))) {
        const after = m[1];
        const same = after.indexOf('```');
        if (same > 0) {
          blocks.push({ t: 'code', lang: '', v: after.slice(0, same) });
          open = null;
          continue;
        }
        if (same === -1) {
          let k = i + 1;
          while (k < lines.length && !lines[k].includes('```')) k++;
          if (k < lines.length) {
            const body = [];
            const lang = /^[\w+#.-]{1,20}$/.test(after.trim()) ? after.trim() : '';
            if (!lang && after.trim()) body.push(after);
            body.push(...lines.slice(i + 1, k));
            const tail = lines[k].slice(0, lines[k].indexOf('```'));
            if (tail.trim()) body.push(tail);
            blocks.push({ t: 'code', lang, v: body.join('\n') });
            open = null;
            i = k;
            continue;
          }
        }
      }

      if (!inQuote) {
        if ((m = line.match(/^>>> (.*)$/))) {
          blocks.push({ t: 'quote', c: parse([m[1], ...lines.slice(i + 1)].join('\n'), true) });
          return blocks;
        }
        if (QUOTE.test(line)) {
          const q = [];
          while (i < lines.length && QUOTE.test(lines[i])) q.push(lines[i++].slice(2));
          i--;
          blocks.push({ t: 'quote', c: parse(q.join('\n'), true) });
          open = null;
          continue;
        }
      }

      if ((m = line.match(/^(#{1,3}) +(\S.*)$/))) {
        blocks.push({ t: 'h', level: m[1].length, c: inline(m[2].trim()) });
        open = null;
        continue;
      }
      if ((m = line.match(/^-# +(\S.*)$/))) {
        blocks.push({ t: 'sub', c: inline(m[1]) });
        open = null;
        continue;
      }
      if ((m = line.match(/^( *)([-*]|\d{1,9}\.) +(\S.*)$/))) {
        const o = m[2].endsWith('.');
        const item = { d: Math.min(Math.floor(m[1].length / 2), 3), o, n: o ? parseInt(m[2], 10) : null, c: inline(m[3]) };
        if (open?.t === 'list') open.items.push(item);
        else { open = { t: 'list', items: [item] }; blocks.push(open); }
        continue;
      }
      if (!line.trim()) { open = null; continue; }

      if (open?.t === 'p') open.lines.push(inline(line));
      else { open = { t: 'p', lines: [inline(line)] }; blocks.push(open); }
    }
    return blocks;
  }

  // The first lines of a description, for the card on the board: block marks dropped (a
  // heading goes bold, an item keeps its bullet), at most `max` of them.
  function snippetLines(blocks, max = 2) {
    const out = [];
    const walk = (bs) => {
      for (const b of bs) {
        if (out.length >= max) return;
        if (b.t === 'p') out.push(...b.lines.slice(0, max - out.length));
        else if (b.t === 'h') out.push([{ t: 'b', c: b.c }]);
        else if (b.t === 'sub') out.push(b.c);
        else if (b.t === 'quote') walk(b.c);
        else if (b.t === 'list') {
          for (const it of b.items.slice(0, max - out.length)) out.push([{ t: 'text', v: it.o ? `${it.n}. ` : '• ' }, ...it.c]);
        } else if (b.t === 'code' && b.v.trim()) out.push([{ t: 'mono', v: b.v.split('\n').find((l) => l.trim()) }]);
      }
    };
    walk(blocks);
    return out;
  }

  /* ---- drawing ---- */

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

  // `still`: on a card on the board, where a press opens the card: links are only coloured,
  // and spoilers stay hidden.
  function inlineHtml(nodes, still) {
    return nodes.map((n) => {
      switch (n.t) {
        case 'text': return esc(n.v);
        case 'mono': return `<code class="md-mono">${esc(n.v)}</code>`;
        case 'b': return `<strong>${inlineHtml(n.c, still)}</strong>`;
        case 'i': return `<em>${inlineHtml(n.c, still)}</em>`;
        case 'u': return `<u>${inlineHtml(n.c, still)}</u>`;
        case 's': return `<s>${inlineHtml(n.c, still)}</s>`;
        case 'spoiler':
          return still
            ? `<span class="md-spoiler" aria-label="Spoiler"><span aria-hidden="true">${inlineHtml(n.c, still)}</span></span>`
            : `<span class="md-spoiler" tabindex="0" role="button" aria-label="Spoiler, press to show"><span aria-hidden="true">${inlineHtml(n.c, still)}</span></span>`;
        case 'link':
          return still
            ? `<span class="md-link">${inlineHtml(n.c, still)}</span>`
            : `<a class="md-link" href="${esc(n.href)}" target="_blank" rel="noopener noreferrer nofollow">${inlineHtml(n.c, still)}</a>`;
        default: return '';
      }
    }).join('');
  }

  function blocksHtml(blocks) {
    return blocks.map((b) => {
      switch (b.t) {
        case 'p': return `<p>${b.lines.map((l) => inlineHtml(l)).join('<br>')}</p>`;
        case 'h': return `<div class="md-h md-h${b.level}" role="heading" aria-level="${b.level + 2}">${inlineHtml(b.c)}</div>`;
        case 'sub': return `<p class="md-sub">${inlineHtml(b.c)}</p>`;
        case 'quote': return `<blockquote class="md-quote">${blocksHtml(b.c)}</blockquote>`;
        case 'code': return `<pre class="md-pre"><code>${esc(b.v)}</code></pre>`;
        case 'list':
          return `<div class="md-list" role="list">${b.items.map((it) =>
            `<div class="md-li" role="listitem" style="--d:${it.d}"><span class="md-bullet" aria-hidden="true">${it.o ? `${it.n}.` : '•'}</span><span>${inlineHtml(it.c)}</span></div>`).join('')}</div>`;
        default: return '';
      }
    }).join('');
  }

  const toHtml = (src) => blocksHtml(parse(src));
  const snippetHtml = (src) => snippetLines(parse(src)).map((l) => inlineHtml(l, true)).join('<br>');

  // A spoiler pressed (or Enter/Space on it) shows what it hides. Wired once per container.
  function wireSpoilers(root) {
    const reveal = (el) => {
      el.classList.add('shown');
      el.removeAttribute('role');
      el.removeAttribute('tabindex');
      el.removeAttribute('aria-label');
      el.firstElementChild?.removeAttribute('aria-hidden');
    };
    root.addEventListener('click', (e) => {
      const el = e.target.closest('.md-spoiler[role="button"]');
      if (el) { e.stopPropagation(); reveal(el); }
    });
    root.addEventListener('keydown', (e) => {
      const el = e.target.closest?.('.md-spoiler[role="button"]');
      if (el && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); reveal(el); }
    });
  }

  /* ---- the toolbar ---- */

  // Wraps the selection in a mark (or puts an empty pair at the caret), makes it a link, or
  // starts each selected line with "- ". The field's own input event follows, as typing would.
  function format(ta, kind) {
    const { selectionStart: a, selectionEnd: b, value } = ta;
    const sel = value.slice(a, b);
    const marks = { bold: '**', italic: '*', strike: '~~', code: '`', spoiler: '||', underline: '__' };
    let text, from, to;
    if (marks[kind]) {
      const m = marks[kind];
      text = m + sel + m;
      from = a + m.length;
      to = from + sel.length;
    } else if (kind === 'link') {
      const isUrl = /^https?:\/\/\S+$/.test(sel);
      text = isUrl ? `[](${sel})` : `[${sel || 'link'}](https://)`;
      from = isUrl ? a + 1 : a + text.length - 9;
      to = isUrl ? from : a + text.length - 1;
    } else if (kind === 'list') {
      const start = a === 0 ? 0 : value.lastIndexOf('\n', a - 1) + 1;
      const endNl = value.indexOf('\n', b);
      const end = endNl === -1 ? value.length : endNl;
      const lines = value.slice(start, end).split('\n');
      const all = lines.every((l) => /^- /.test(l));
      text = lines.map((l) => (all ? l.slice(2) : `- ${l}`)).join('\n');
      ta.setRangeText(text, start, end, 'end');
      ta.focus();
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    } else return;
    ta.setRangeText(text, a, b, 'end');
    ta.setSelectionRange(from, to);
    ta.focus();
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  }

  window.Markdown = { parse, inline, snippetLines, toHtml, snippetHtml, wireSpoilers, format };
})();
