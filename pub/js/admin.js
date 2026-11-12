/* roytalk -- the author's desk: preview and confirmations. No dependencies. */
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

  function refresh() {
    var body = new URLSearchParams();
    body.set('csrf', form.elements.csrf.value);
    body.set('body_md', form.elements.body_md.value);
    btn.disabled = true;
    fetch('/admin/preview', { method: 'POST', body: body, credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (html) { out.innerHTML = html; })
      .catch(function () { out.insertAdjacentHTML('afterbegin', '<p class="notice error">Preview failed.</p>'); })
      .then(function () { btn.disabled = false; });
  }
  btn.addEventListener('click', refresh);
  // Ctrl/Cmd+S saves, Ctrl/Cmd+Enter refreshes the preview.
  form.elements.body_md.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); refresh(); }
    if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); form.requestSubmit(form.querySelector('[name=action][value=save]')); }
  });
})();
