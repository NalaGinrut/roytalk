<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px;max-width:820px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">Sponsors</h1>
<p class="muted small">One plain line of text per slot. No images, no scripts, no tracking. Links carry rel="sponsored".</p>
<% (for-each (lambda (s) %>
<form method="post" action=<%= (qa "/admin/sponsors/" (row-ref s "slot")) %> style="margin-top:32px;padding-top:24px;border-top:1px solid var(--ink);display:flex;flex-direction:column;gap:16px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<h2 class="eyebrow" style="margin:0"><%= (if (equal? (row-ref s "slot") "home") "Home page, side column" "Under each essay") %></h2>
<div class="field"><label for=<%= (qa "n-" (row-ref s "slot")) %>>Sponsor name</label><input id=<%= (qa "n-" (row-ref s "slot")) %> name="name" type="text" maxlength="80" value=<%= (qa (row-ref s "name")) %>></div>
<div class="field"><label for=<%= (qa "l-" (row-ref s "slot")) %>>One sentence</label><input id=<%= (qa "l-" (row-ref s "slot")) %> name="line" type="text" maxlength="160" value=<%= (qa (row-ref s "line")) %>></div>
<div class="field"><label for=<%= (qa "u-" (row-ref s "slot")) %>>Link</label><input id=<%= (qa "u-" (row-ref s "slot")) %> name="url" type="url" value=<%= (qa (row-ref s "url")) %>></div>
<label style="display:flex;gap:10px;align-items:center"><input type="checkbox" name="active"<%= (checked (row-ref s "active")) %>> Show it</label>
<div><button class="btn" type="submit">Save</button></div>
</form>
<% ) slots) %>
</main>
<@include admin/bottom.html.tpl %>
