/* roytalk -- the author's desk: preview, image upload, confirmations.
   No dependencies, ES5. */
(function () {
  'use strict';

  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-confirm]');
    if (b && !window.confirm(b.getAttribute('data-confirm'))) e.preventDefault();
  });

  var form = document.getElementById('editor');
  var btn = document.querySelector('[data-preview]');
  var out = document.getElementById('preview');
  if (!form || !btn || !out) return;

  var ta = form.elements.body_md;
  var statusEl = document.getElementById('upload-status');
  var pickBtn = document.querySelector('[data-pick-image]');
  var fileInput = document.getElementById('image-input');
  var tools = document.getElementById('image-tools');
  var widthInput = document.getElementById('img-width');
  var widthOut = document.getElementById('img-width-out');
  var toolsStatus = document.getElementById('image-tools-status');

  var MAX_BYTES = 10 * 1024 * 1024;
  var ALLOWED = { 'image/png': 1, 'image/jpeg': 1, 'image/gif': 1, 'image/webp': 1 };

  var selected = null;   /* {id, src} of the image being edited */
  var current = null;    /* {img, token, fit} */
  var refreshSeq = 0;

  function rand() {
    return Math.random().toString(16).slice(2, 10);
  }

  function cssPx(name, fallback) {
    var v = window.getComputedStyle(document.documentElement).getPropertyValue(name);
    var n = parseFloat(v);
    return n > 0 ? n : fallback;
  }

  function measurePx() { return cssPx('--measure', 640); }

  /* ------------------------------------------------------------ preview */

  function previewImage() {
    if (!selected) return null;
    if (selected.id) {
      var el = document.getElementById(selected.id);
      if (el && el.tagName === 'IMG' && out.contains(el)) return el;
    }
    var imgs = out.getElementsByTagName('img');
    for (var i = 0; i < imgs.length; i++) {
      if (imgs[i].getAttribute('src') === selected.src) return imgs[i];
    }
    return null;
  }

  function refresh() {
    var seq = ++refreshSeq;
    var body = new URLSearchParams();
    body.set('csrf', form.elements.csrf.value);
    body.set('body_md', ta.value);
    btn.disabled = true;
    return fetch('/admin/preview', { method: 'POST', body: body, credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (html) {
        if (seq !== refreshSeq) return;
        var top = out.scrollTop;
        out.innerHTML = html;
        out.scrollTop = top;
        if (selected) {
          var img = previewImage();
          if (img) selectImage(img); else closeTools();
        }
      })
      .catch(function () {
        if (seq !== refreshSeq) return;
        out.insertAdjacentHTML('afterbegin', '<p class="notice error">Preview failed.</p>');
      })
      .then(function () { if (seq === refreshSeq) btn.disabled = false; });
  }
  btn.addEventListener('click', function () { refresh(); });

  /* ------------------------------------------------------------ markdown mapping */

  function spaces(n) {
    var s = '';
    while (n-- > 0) s += ' ';
    return s;
  }

  function maskInline(line) {
    var chars = line.split('');
    var i = 0;
    while (i < line.length) {
      if (line.charAt(i) !== '`') { i++; continue; }
      var j = i;
      while (j < line.length && line.charAt(j) === '`') j++;
      var run = j - i;
      var close = findRun(line, j, run);
      if (close < 0) { i = j; continue; }
      for (var k = i; k < close + run; k++) chars[k] = ' ';
      i = close + run;
    }
    return chars.join('');
  }

  function findRun(s, from, n) {
    var i = from;
    while (i < s.length) {
      if (s.charAt(i) !== '`') { i++; continue; }
      var j = i;
      while (j < s.length && s.charAt(j) === '`') j++;
      if (j - i === n) return i;
      i = j;
    }
    return -1;
  }

  /* Replace fenced and inline code with spaces, keeping offsets. */
  function maskCode(s) {
    var lines = s.split('\n');
    var fence = null;
    var res = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var m = /^ {0,3}(`{3,}|~{3,})/.exec(line);
      if (fence) {
        if (m && m[1].charAt(0) === fence.charAt(0) && m[1].length >= fence.length &&
            !/\S/.test(line.slice(m[0].length))) {
          fence = null;
        }
        res.push(spaces(line.length));
      } else if (m) {
        fence = m[1];
        res.push(spaces(line.length));
      } else {
        res.push(maskInline(line));
      }
    }
    return res.join('\n');
  }

  var IMG_RE = /!\[([^\]\n]*)\]\(\s*([^\s)\n]+)(?:\s+"[^"]*")?\s*\)(\{[^}\n]*\})?/g;

  function makeToken(m) {
    return {
      start: m.index,
      end: m.index + m[0].length,
      alt: m[1],
      src: m[2],
      attrs: m[3] ? m[3].slice(1, -1) : ''
    };
  }

  /* Find the Markdown token for a rendered image. A unique id is exact even
     when the same file is used twice; src is the fallback for older posts. */
  function findToken(id, src) {
    var masked = maskCode(ta.value);
    var re = new RegExp(IMG_RE.source, 'g');
    var fallback = [];
    var m;
    while ((m = re.exec(masked))) {
      var token = makeToken(m);
      if (id) {
        var hit = /(?:^|\s)#([A-Za-z0-9_-]+)/.exec(token.attrs);
        if (hit && hit[1] === id) return token;
      } else if (token.src === src) {
        fallback.push(token);
      }
    }
    return fallback.length === 1 ? fallback[0] : null;
  }

  function attrParts(attrs) {
    return attrs ? attrs.split(/\s+/).filter(function (p) { return p; }) : [];
  }

  function renderToken(src, alt, parts) {
    return '![' + alt + '](' + src + ')' + (parts.length ? '{' + parts.join(' ') + '}' : '');
  }

  function widthOf(attrs) {
    var m = /(?:^|\s)width="?([0-9.]+)(%?)"?/.exec(attrs);
    return m ? { value: parseFloat(m[1]), percent: m[2] === '%' } : null;
  }

  function replaceRange(start, end, text) {
    var value = ta.value;
    var selS = ta.selectionStart;
    var selE = ta.selectionEnd;
    var delta = text.length - (end - start);
    if (typeof ta.setRangeText === 'function') {
      ta.setRangeText(text, start, end, 'preserve');
    } else {
      ta.value = value.slice(0, start) + text + value.slice(end);
    }
    function map(pos) {
      if (pos >= end) return pos + delta;
      if (pos >= start) return start + text.length;
      return pos;
    }
    try { ta.setSelectionRange(map(selS), map(selE)); } catch (err) {}
  }

  function replaceToken(token, text) {
    replaceRange(token.start, token.end, text);
    /* Keep the span usable while the preview round-trip is in flight; the
       next refresh replaces it with a freshly mapped one. */
    var m = /^!\[([^\]]*)\]\(([^)]*)\)\{([^}]*)\}$/.exec(text);
    return { start: token.start, end: token.start + text.length,
             alt: m ? m[1] : token.alt, src: m ? m[2] : token.src,
             attrs: m ? m[3] : '' };
  }

  /* ------------------------------------------------------------ blocks */

  function blocks(s) {
    var re = /\n[ \t]*\n/g;
    var res = [];
    var start = 0;
    var m;
    while ((m = re.exec(s))) {
      res.push({ start: start, end: m.index });
      start = re.lastIndex;
    }
    res.push({ start: start, end: s.length });
    return res;
  }

  function blockAt(bs, pos) {
    for (var i = 0; i < bs.length; i++) {
      if (pos >= bs[i].start && (pos < bs[i].end || i === bs.length - 1)) return i;
    }
    return -1;
  }

  function neighbor(bs, i, dir) {
    var j = i + dir;
    while (j >= 0 && j < bs.length) {
      if (/\S/.test(ta.value.slice(bs[j].start, bs[j].end))) return j;
      j += dir;
    }
    return -1;
  }

  function moveBlock(token, dir) {
    var bs = blocks(ta.value);
    var i = blockAt(bs, token.start);
    var j = neighbor(bs, i, dir);
    if (i < 0 || j < 0) return false;
    var a = Math.min(i, j);
    var b = Math.max(i, j);
    var value = ta.value;
    var first = value.slice(bs[a].start, bs[a].end);
    var second = value.slice(bs[b].start, bs[b].end);
    var sep = value.slice(bs[a].end, bs[b].start);
    replaceRange(bs[a].start, bs[b].end, second + sep + first);
    return true;
  }

  /* ------------------------------------------------------------ image tools */

  function closeTools() {
    selected = null;
    current = null;
    tools.hidden = true;
    var prev = out.querySelector('img.is-selected');
    if (prev) prev.classList.remove('is-selected');
  }

  function setToolsEnabled(on) {
    var els = tools.querySelectorAll('[data-img-align], [data-img-move], #img-width');
    for (var i = 0; i < els.length; i++) els[i].disabled = !on;
  }

  function moveButton(dir) {
    return tools.querySelector('[data-img-move="' + dir + '"]');
  }

  function selectImage(img) {
    var prev = out.querySelector('img.is-selected');
    if (prev && prev !== img) prev.classList.remove('is-selected');
    img.classList.add('is-selected');

    var id = img.getAttribute('id') || '';
    if (!/^img-/.test(id)) id = '';
    selected = { id: id, src: img.getAttribute('src') || '' };
    current = { img: img, token: null, fit: 0 };
    tools.hidden = false;

    var token = findToken(id, selected.src);
    if (!token) {
      current.token = null;
      setToolsEnabled(false);
      toolsStatus.textContent = 'This image has no editable Markdown reference; edit the text by hand.';
      return;
    }
    current.token = token;
    setToolsEnabled(true);
    toolsStatus.textContent = 'Moves the image paragraph.';

    var measure = measurePx();
    current.fit = Math.min(img.naturalWidth || measure, measure);
    var w = widthOf(token.attrs);
    var pct = !w ? 100
      : (w.percent ? w.value : (w.value / current.fit * 100));
    pct = Math.max(10, Math.min(100, Math.round(pct)));
    widthInput.value = String(pct);
    widthOut.textContent = Math.max(16, Math.round(current.fit * pct / 100)) + 'px';

    var bs = blocks(ta.value);
    var idx = blockAt(bs, token.start);
    var up = moveButton('up');
    var down = moveButton('down');
    if (up) up.disabled = idx < 0 || neighbor(bs, idx, -1) < 0;
    if (down) down.disabled = idx < 0 || neighbor(bs, idx, 1) < 0;
  }

  function applyWidth() {
    if (!current || !current.token) return;
    var pct = parseInt(widthInput.value, 10);
    var px = Math.max(16, Math.round(current.fit * pct / 100));
    var parts = attrParts(current.token.attrs).filter(function (p) {
      return !/^width=/.test(p);
    });
    if (pct < 100) parts.push('width=' + px);
    current.token = replaceToken(current.token,
                                 renderToken(current.token.src, current.token.alt, parts));
    refresh();
  }

  function applyAlign(align) {
    if (!current || !current.token) return;
    var parts = attrParts(current.token.attrs).filter(function (p) {
      return !/^\.img-(left|center|right)$/.test(p);
    });
    if (align !== 'left') parts.push('.img-' + align);
    current.token = replaceToken(current.token,
                                 renderToken(current.token.src, current.token.alt, parts));
    refresh();
  }

  out.addEventListener('click', function (e) {
    var img = e.target.closest ? e.target.closest('img') : null;
    if (!img || !out.contains(img)) return;
    e.preventDefault();
    selectImage(img);
  });

  tools.addEventListener('click', function (e) {
    if (e.target.closest('[data-img-close]')) { closeTools(); return; }
    var align = e.target.closest('[data-img-align]');
    if (align) { applyAlign(align.getAttribute('data-img-align')); return; }
    var move = e.target.closest('[data-img-move]');
    if (move && current && current.token) {
      if (moveBlock(current.token, move.getAttribute('data-img-move') === 'up' ? -1 : 1)) {
        current.token = null;
        refresh();
      }
    }
  });

  widthInput.addEventListener('input', function () {
    if (!current || !current.token) return;
    var pct = parseInt(widthInput.value, 10);
    var px = Math.max(16, Math.round(current.fit * pct / 100));
    current.img.style.width = px + 'px';
    widthOut.textContent = px + 'px';
  });
  widthInput.addEventListener('change', applyWidth);

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !tools.hidden) closeTools();
  });
  document.addEventListener('click', function (e) {
    if (tools.hidden) return;
    if (tools.contains(e.target)) return;
    if (e.target.closest && e.target.closest('#preview img')) return;
    closeTools();
  });

  var syncTimer = null;
  ta.addEventListener('input', function () {
    clearTimeout(syncTimer);
    syncTimer = setTimeout(function () {
      if (!selected) return;
      var img = previewImage();
      if (img) selectImage(img); else closeTools();
    }, 200);
  });

  /* ------------------------------------------------------------ upload */

  function setStatus(msg, isError) {
    if (!statusEl) return;
    statusEl.textContent = msg || '';
    statusEl.style.color = isError ? 'var(--red, #8a1c1c)' : '';
  }

  function friendly(code) {
    if (code === 'too-large') return 'larger than 10 MB';
    if (code === 'empty') return 'empty';
    if (code === 'unsupported' || code === 'unsupported-type') return 'not a PNG, JPEG, GIF or WebP';
    if (code === 'csrf') return 'the session has expired; sign in again';
    if (code === 'write-failed') return 'the server could not save it';
    return 'the upload was rejected';
  }

  function altText(name) {
    var s = (name || 'image').replace(/\\/g, '/').split('/').pop();
    s = s.replace(/\.[A-Za-z0-9]+$/, '');
    s = s.replace(/[\[\]\r\n]/g, ' ').replace(/\s+/g, ' ').trim();
    return s.slice(0, 120) || 'image';
  }

  function replacePlaceholder(text, replacement) {
    var i = ta.value.indexOf(text);
    if (i < 0) return false;
    replaceRange(i, i + text.length, replacement);
    return true;
  }

  function uploadOne(file, placeholder) {
    var fd = new FormData();
    fd.append('csrf', form.elements.csrf.value);
    fd.append('file', file);
    return fetch('/admin/upload', { method: 'POST', body: fd, credentials: 'same-origin' })
      .then(function (r) {
        return r.text().then(function (text) {
          var data = null;
          try { data = JSON.parse(text); } catch (err) {}
          if (!r.ok || !data) {
            throw new Error((data && data.errors && data.errors[0] && data.errors[0].error) ||
                            ('http-' + r.status));
          }
          if (!data.files || !data.files.length) {
            throw new Error((data.errors && data.errors[0] && data.errors[0].error) || 'rejected');
          }
          return data.files[0];
        });
      })
      .then(function (f) {
        var md = '![' + altText(f.name) + '](' + f.url + '){#' +
                 'img-' + rand() + rand() + '}';
        replacePlaceholder(placeholder, md);
      })
      .catch(function (err) {
        replacePlaceholder(placeholder, '');
        setStatus('Image upload failed: ' +
                  (err && err.message && err.message.indexOf('http-') === 0
                     ? 'upload failed (' + err.message.slice(5) + ')'
                     : friendly(err && err.message)), true);
      });
  }

  function uploadFiles(list, insertAt) {
    var accepted = [];
    for (var i = 0; i < list.length; i++) {
      var f = list[i];
      if (!ALLOWED[f.type] && !/\.(png|jpe?g|gif|webp)$/i.test(f.name || '')) {
        setStatus('Skipped ' + (f.name || 'a file') + ': not a PNG, JPEG, GIF or WebP.', true);
        continue;
      }
      if (f.size > MAX_BYTES) {
        setStatus('Skipped ' + (f.name || 'an image') + ': larger than 10 MB.', true);
        continue;
      }
      accepted.push(f);
    }
    if (!accepted.length) return;

    var placeholders = [];
    var block = '\n\n';
    for (var j = 0; j < accepted.length; j++) {
      var ph = '![Uploading rt-' + rand() + '…]()';
      placeholders.push(ph);
      block += ph + '\n\n';
    }
    replaceRange(insertAt, insertAt, block);
    setStatus('Uploading ' + accepted.length + ' image' + (accepted.length > 1 ? 's' : '') + '…');

    var chain = Promise.resolve();
    accepted.forEach(function (file, k) {
      chain = chain.then(function () { return uploadOne(file, placeholders[k]); });
    });
    chain.then(function () {
      if (statusEl && /^Uploading/.test(statusEl.textContent)) setStatus('');
      refresh();
    });
  }

  function clipboardImages(cd) {
    var files = [];
    if (cd.items) {
      for (var i = 0; i < cd.items.length; i++) {
        var it = cd.items[i];
        if (it.kind === 'file' && /^image\//.test(it.type)) {
          var f = it.getAsFile();
          if (f) files.push(f);
        }
      }
    }
    if (!files.length && cd.files) {
      for (var j = 0; j < cd.files.length; j++) {
        if (/^image\//.test(cd.files[j].type)) files.push(cd.files[j]);
      }
    }
    return files;
  }

  ta.addEventListener('paste', function (e) {
    var files = e.clipboardData ? clipboardImages(e.clipboardData) : [];
    if (!files.length) return;  /* ordinary text paste */
    e.preventDefault();
    uploadFiles(files, ta.selectionStart);
  });

  ['dragenter', 'dragover'].forEach(function (ev) {
    ta.addEventListener(ev, function (e) {
      e.preventDefault();
      ta.classList.add('drop-target');
    });
  });
  ta.addEventListener('dragleave', function () { ta.classList.remove('drop-target'); });
  ta.addEventListener('drop', function (e) {
    e.preventDefault();
    ta.classList.remove('drop-target');
    if (!e.dataTransfer) return;
    var files = [];
    for (var i = 0; i < e.dataTransfer.files.length; i++) files.push(e.dataTransfer.files[i]);
    if (files.length) uploadFiles(files, ta.selectionStart);
  });

  if (pickBtn && fileInput) {
    pickBtn.addEventListener('click', function () { fileInput.click(); });
    fileInput.addEventListener('change', function () {
      var files = [];
      for (var i = 0; i < fileInput.files.length; i++) files.push(fileInput.files[i]);
      uploadFiles(files, ta.selectionStart);
      fileInput.value = '';
    });
  }

  /* Ctrl/Cmd+S saves, Ctrl/Cmd+Enter refreshes the preview. */
  ta.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); refresh(); }
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      form.requestSubmit(form.querySelector('[name=action][value=save]'));
    }
  });
})();
