/* roytalk -- the little that needs a script. The site reads fine without it.
 *
 *  - shows "@handle" instead of "Sign in" on cached pages (display cookie only)
 *  - marks quoted sentences and puts readers' questions in the margin
 *  - select a sentence in an essay to question it; the selection survives
 *    signing in (kept in localStorage for an hour)
 *  - counts a read once a page has been open for a while
 *
 * No dependencies, no third parties, no tracking. GPLv3 or later.
 */
(function () {
  'use strict';

  var WIDE = window.matchMedia('(min-width: 1100px)');
  var PENDING_KEY = 'roytalk.pending-question';
  var MAX_QUOTE = 600;
  var CONTEXT = 48;

  function cookie(name) {
    var m = document.cookie.match('(?:^|; )' + name + '=([^;]*)');
    return m ? decodeURIComponent(m[1]) : '';
  }
  var handle = cookie('rt_handle');
  var csrf = cookie('rt_csrf');
  var signedIn = !!csrf;

  /* ------------------------------------------------------------ account link */
  if (signedIn) {
    document.querySelectorAll('[data-account]').forEach(function (a) {
      a.textContent = handle ? '@' + handle : 'Your account';
      a.setAttribute('href', '/me');
    });
  }

  var prose = document.querySelector('article.prose[data-slug]');
  if (!prose) return;
  var slug = prose.getAttribute('data-slug');

  /* ------------------------------------------------------------ read count */
  (function () {
    var sent = false;
    function send() {
      if (sent || document.visibilityState !== 'visible') return;
      sent = true;
      var url = '/posts/' + encodeURIComponent(slug) + '/read';
      if (navigator.sendBeacon) navigator.sendBeacon(url, '');
      else fetch(url, { method: 'POST', keepalive: true });
    }
    setTimeout(send, 8000);
  })();

  /* ------------------------------------------------------------ text index
   * The essay's text with runs of white space collapsed, and for every
   * character the text node and offset it came from. Quotes are stored and
   * matched in this collapsed form, so line breaks and indentation in the
   * HTML do not matter.
   */
  function squash(s) { return s.replace(/\s+/g, ' ').trim(); }
  function plainQuotes(s) { return s.replace(/[‘’]/g, "'").replace(/[“”]/g, '"'); }

  function buildIndex() {
    var text = '', map = [], space = true;
    var walker = document.createTreeWalker(prose, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        return n.parentNode.closest('.q-bubble, .ask-pop, a[aria-hidden], annotation')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    var node;
    while ((node = walker.nextNode())) {
      var v = node.nodeValue;
      for (var i = 0; i < v.length; i++) {
        var c = v[i];
        if (/\s/.test(c)) {
          if (space) continue;
          text += ' '; space = true;
        } else {
          text += c; space = false;
        }
        map.push([node, i]);
      }
    }
    return { text: plainQuotes(text), map: map };
  }

  function rangeAt(index, start, length) {
    var a = index.map[start], b = index.map[start + length - 1];
    if (!a || !b) return null;
    var r = document.createRange();
    r.setStart(a[0], a[1]);
    r.setEnd(b[0], b[1] + 1);
    return r;
  }

  function locate(index, exact, prefix, suffix) {
    exact = plainQuotes(squash(exact || ''));
    if (!exact) return -1;
    prefix = plainQuotes(squash(prefix || ''));
    suffix = plainQuotes(squash(suffix || ''));
    var best = -1, bestScore = -1, at = index.text.indexOf(exact);
    while (at !== -1) {
      var score = 0;
      var before = index.text.slice(Math.max(0, at - prefix.length - 1), at).trim();
      var after = index.text.slice(at + exact.length, at + exact.length + suffix.length + 1).trim();
      if (prefix && before.slice(-Math.min(prefix.length, 16)) === prefix.slice(-Math.min(prefix.length, 16))) score += 2;
      if (suffix && after.slice(0, Math.min(suffix.length, 16)) === suffix.slice(0, Math.min(suffix.length, 16))) score += 2;
      if (score > bestScore) { best = at; bestScore = score; }
      at = index.text.indexOf(exact, at + 1);
    }
    return best;
  }

  /* Wrap every text node piece inside RANGE in <mark>; returns the marks. */
  function highlight(range, cls, id) {
    var marks = [];
    var nodes = [];
    var walker = document.createTreeWalker(range.commonAncestorContainer.nodeType === 3
      ? range.commonAncestorContainer.parentNode : range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    var n;
    while ((n = walker.nextNode())) if (range.intersectsNode(n)) nodes.push(n);
    nodes.forEach(function (node) {
      var start = node === range.startContainer ? range.startOffset : 0;
      var end = node === range.endContainer ? range.endOffset : node.nodeValue.length;
      if (end <= start || !node.nodeValue.slice(start, end).trim()) return;
      var piece = node;
      if (start > 0) piece = piece.splitText(start);
      if (end - start < piece.nodeValue.length) piece.splitText(end - start);
      var mark = document.createElement('mark');
      mark.className = cls;
      if (id) mark.setAttribute('data-q', id);
      piece.parentNode.insertBefore(mark, piece);
      mark.appendChild(piece);
      marks.push(mark);
    });
    return marks;
  }

  function unwrap(marks) {
    marks.forEach(function (m) {
      var p = m.parentNode;
      if (!p) return;
      while (m.firstChild) p.insertBefore(m.firstChild, m);
      p.removeChild(m);
      p.normalize();
    });
  }

  function topIn(el) {
    return el.getBoundingClientRect().top - prose.getBoundingClientRect().top;
  }

  /* ------------------------------------------------------------ question bubble
   * Quoted sentences are normally unmarked. Hovering or focusing one opens a
   * bubble with the newest questions on that passage. Clicking a sentence
   * pins the bubble (and gives touch screens a way to open it).
   */
  var bubble = null, bubbleFor = null, bubbleTimer = null, bubblePinned = false;

  function cancelBubbleTimer() {
    if (bubbleTimer) { clearTimeout(bubbleTimer); bubbleTimer = null; }
  }

  function clearBubble() {
    cancelBubbleTimer();
    if (bubble) { bubble.remove(); bubble = null; }
    if (bubbleFor) {
      bubbleFor.marks.forEach(function (m) { m.classList.remove('is-active'); });
      bubbleFor = null;
    }
    bubblePinned = false;
  }

  function scheduleHide() {
    cancelBubbleTimer();
    if (bubblePinned) return;
    bubbleTimer = setTimeout(clearBubble, 180);
  }

  function bubbleExcerpt(s) {
    s = squash(s);
    if (s.length <= 120) return s;
    var cut = s.slice(0, 117);
    var sp = cut.lastIndexOf(' ');
    return (sp > 0 ? cut.slice(0, sp) : cut) + '…';
  }

  function buildBubble(cluster) {
    var box = document.createElement('div');
    box.className = 'q-bubble on';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'Questions on this sentence');

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'close';
    close.setAttribute('aria-label', 'Close');
    close.textContent = '×';
    close.addEventListener('click', clearBubble);
    box.appendChild(close);

    var title = document.createElement('div');
    title.className = 'eyebrow';
    title.textContent = cluster.entries.length === 1
      ? 'One question on this sentence'
      : cluster.entries.length + ' questions on this sentence';
    box.appendChild(title);

    // Newest first; each entry may stand for several merged askers.
    var entries = cluster.entries.slice().sort(function (a, b) { return b.order - a.order; });
    entries.slice(0, 3).forEach(function (e) {
      var a = document.createElement('a');
      a.href = '#' + e.q.id;
      a.addEventListener('click', function () { clearBubble(); });
      var who = document.createElement('span');
      who.className = 'who';
      who.textContent = e.handle;
      a.appendChild(who);
      if (e.askers > 1) {
        var n = document.createElement('span');
        n.className = 'count';
        n.textContent = ' · ' + e.askers + ' people asked';
        a.appendChild(n);
      }
      var said = document.createElement('span');
      said.className = 'said';
      said.textContent = bubbleExcerpt(e.body);
      a.appendChild(said);
      box.appendChild(a);
    });

    if (entries.length > 3) {
      var more = document.createElement('a');
      more.href = '#questions';
      more.className = 'more';
      more.textContent = 'See all ' + entries.length + ' questions';
      more.addEventListener('click', function () { clearBubble(); });
      box.appendChild(more);
    }

    box.addEventListener('mouseenter', cancelBubbleTimer);
    box.addEventListener('mouseleave', scheduleHide);
    box.addEventListener('focusin', cancelBubbleTimer);
    box.addEventListener('focusout', function () {
      setTimeout(function () {
        if (bubble && !bubble.contains(document.activeElement)) scheduleHide();
      }, 0);
    });
    return box;
  }

  function positionBubble() {
    if (!bubble || !bubbleFor) return;
    bubble.style.top = Math.max(0, topIn(bubbleFor.marks[0])) + 'px';
  }

  function showBubble(cluster) {
    if (pop) return; // the ask form has the stage
    cancelBubbleTimer();
    if (bubble && bubbleFor === cluster) return;
    clearBubble();
    bubble = buildBubble(cluster);
    bubbleFor = cluster;
    bubbleFor.marks.forEach(function (m) { m.classList.add('is-active'); });
    prose.appendChild(bubble);
    positionBubble();
  }

  function toggleBubble(cluster) {
    if (bubble && bubbleFor === cluster && bubblePinned) {
      clearBubble();
    } else {
      showBubble(cluster);
      if (bubble) bubblePinned = true;
    }
  }

  (function markQuestions() {
    var qs = document.querySelectorAll('.questions .q[data-quote]');
    if (!qs.length) return;
    var index = buildIndex();
    var found = [];
    qs.forEach(function (q, order) {
      var exact = q.getAttribute('data-quote');
      if (!exact) return;
      var at = locate(index, exact, q.getAttribute('data-prefix'), q.getAttribute('data-suffix'));
      if (at < 0) return;
      var who = q.querySelector('.who-line .handle');
      var body = q.querySelector('.said-body');
      found.push({
        q: q,
        at: at,
        len: plainQuotes(squash(exact)).length,
        order: order,
        handle: who ? who.textContent : 'A reader',
        body: body ? body.textContent : '',
        askers: parseInt(q.getAttribute('data-askers') || '1', 10) || 1
      });
    });
    if (!found.length) return;

    // Questions quoting the same or an overlapping passage share one mark.
    found.sort(function (a, b) { return a.at - b.at || a.order - b.order; });
    var clusters = [];
    found.forEach(function (e) {
      var c = clusters[clusters.length - 1];
      if (c && e.at < c.end) {
        c.end = Math.max(c.end, e.at + e.len);
        c.entries.push(e);
      } else {
        clusters.push({ start: e.at, end: e.at + e.len, entries: [e] });
      }
    });

    // Wrap from the end so earlier offsets stay valid.
    clusters.sort(function (a, b) { return b.start - a.start; });
    clusters.forEach(function (c) {
      var r = rangeAt(index, c.start, c.end - c.start);
      c.marks = r ? highlight(r, 'q-mark') : [];
      if (!c.marks.length) return;
      c.marks.forEach(function (m) {
        m.addEventListener('mouseenter', function () { if (!bubblePinned) showBubble(c); });
        m.addEventListener('mouseleave', scheduleHide);
        m.addEventListener('click', function (e) {
          var sel = window.getSelection();
          if (sel && !sel.isCollapsed) return;
          e.preventDefault();
          toggleBubble(c);
        });
      });
      var first = c.marks[0];
      first.setAttribute('tabindex', '0');
      first.setAttribute('role', 'button');
      first.setAttribute('title', c.entries.length === 1
        ? '1 question on this sentence'
        : c.entries.length + ' questions on this sentence');
      first.addEventListener('focus', function () { if (!bubblePinned) showBubble(c); });
      first.addEventListener('blur', function () {
        setTimeout(function () {
          if (!bubble || !bubble.contains(document.activeElement)) scheduleHide();
        }, 0);
      });
      first.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggleBubble(c); }
        else if (e.key === 'Escape') { clearBubble(); }
      });
    });

    document.addEventListener('mousedown', function (e) {
      if (!bubble) return;
      if (bubble.contains(e.target)) return;
      if (bubbleFor && bubbleFor.marks.some(function (m) { return m.contains(e.target); })) return;
      clearBubble();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape' || !bubble) return;
      var first = bubbleFor && bubbleFor.marks[0];
      // Focus first: the focus handler may reopen the bubble, so clear after.
      if (first) first.focus();
      clearBubble();
    });
    window.addEventListener('resize', positionBubble);
  })();

  /* ------------------------------------------------------------ asking */
  var tpl = document.getElementById('ask-template');
  var pop = null, pendingMarks = [];

  function closePop() {
    if (pop) { pop.remove(); pop = null; }
    unwrap(pendingMarks); pendingMarks = [];
  }

  function savePending(q) {
    try { localStorage.setItem(PENDING_KEY, JSON.stringify(Object.assign({ slug: slug, at: Date.now() }, q))); } catch (e) {}
  }
  function takePending() {
    try {
      var raw = localStorage.getItem(PENDING_KEY);
      if (!raw) return null;
      var p = JSON.parse(raw);
      if (p.slug !== slug) return null;
      localStorage.removeItem(PENDING_KEY);
      return Date.now() - p.at < 3600 * 1000 ? p : null;
    } catch (e) { return null; }
  }

  function openPop(q, anchorTop) {
    clearBubble();
    closePop();
    if (!tpl) return;
    pop = tpl.content.firstElementChild.cloneNode(true);
    var inForm = pop.querySelector('[data-signed-in]');
    var outForm = pop.querySelector('[data-signed-out]');
    if (signedIn) {
      outForm.hidden = true;
      inForm.hidden = false;
      pop.elements.csrf.value = csrf;
      pop.elements.quote_exact.value = q.exact;
      pop.elements.quote_prefix.value = q.prefix;
      pop.elements.quote_suffix.value = q.suffix;
      pop.addEventListener('submit', function () { try { localStorage.removeItem(PENDING_KEY); } catch (e) {} });
    } else {
      var a = pop.querySelector('[data-signin]');
      a.href = '/signin?next=' + encodeURIComponent(location.pathname + '#ask');
      a.addEventListener('click', function () { savePending(q); });
    }
    pop.querySelector('[data-close]').addEventListener('click', closePop);
    pop.addEventListener('keydown', function (e) { if (e.key === 'Escape') closePop(); });
    pop.style.top = Math.max(0, anchorTop) + 'px';
    prose.appendChild(pop);
    var focus = signedIn ? pop.querySelector('textarea') : pop.querySelector('[data-signin]');
    if (focus) focus.focus({ preventScroll: WIDE.matches });
  }

  function selectionQuote() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
    var range = sel.getRangeAt(0);
    if (!prose.contains(range.commonAncestorContainer)) return null;
    var near = range.commonAncestorContainer.nodeType === 3
      ? range.commonAncestorContainer.parentNode
      : range.commonAncestorContainer;
    if (near && near.closest('.ask-pop, .q-bubble')) return null;
    var exact = plainQuotes(squash(sel.toString()));
    if (exact.length < 3 || exact.length > MAX_QUOTE) return null;
    var index = buildIndex();
    // Of all places the words occur, take the one inside the selection.
    var at = index.text.indexOf(exact), chosen = -1;
    while (at !== -1) {
      var p = index.map[at];
      if (p && range.comparePoint(p[0], p[1]) === 0) { chosen = at; break; }
      at = index.text.indexOf(exact, at + 1);
    }
    if (chosen < 0) chosen = index.text.indexOf(exact);
    if (chosen < 0) return null;
    return {
      exact: exact,
      prefix: index.text.slice(Math.max(0, chosen - CONTEXT), chosen),
      suffix: index.text.slice(chosen + exact.length, chosen + exact.length + CONTEXT),
      top: range.getBoundingClientRect().top - prose.getBoundingClientRect().top,
      range: range
    };
  }

  var timer = null;
  function onSelect() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      var q = selectionQuote();
      if (!q) return;
      if (pop && pop.contains(document.activeElement)) return;
      openPop(q, q.top);
    }, 250);
  }
  prose.addEventListener('mouseup', onSelect);
  prose.addEventListener('keyup', function (e) { if (e.shiftKey) onSelect(); });
  // Touch screens: wait for the selection handles to settle.
  document.addEventListener('selectionchange', function () {
    if (!('ontouchstart' in window)) return;
    onSelect();
  });
  document.addEventListener('mousedown', function (e) {
    if (pop && !pop.contains(e.target) && !prose.contains(e.target)) closePop();
  });

  /* ------------------------------------------------------------ back from signing in */
  (function restore() {
    var p = takePending();
    if (!p) return;
    var index = buildIndex();
    var at = locate(index, p.exact, p.prefix, p.suffix);
    if (at < 0) return;
    var r = rangeAt(index, at, p.exact.length);
    if (!r) return;
    var marks = highlight(r, 'q-pending');
    if (!marks.length) return;
    marks[0].scrollIntoView({ block: 'center' });
    openPop(p, topIn(marks[0]));
    pendingMarks = marks; // after openPop, which clears the previous ones
  })();
})();
