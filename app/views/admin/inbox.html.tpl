<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px">
<div class="btn-row" style="justify-content:space-between">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">Inbox</h1>
<p class="small"><% (if (equal? show "all") (begin %><a href="/admin/inbox">Only new</a><% ) (begin %><a href="/admin/inbox?show=all">Everything</a><% )) %></p>
</div>
<p class="muted small">Links readers sent in, most-sent first. Only you see this.</p>
<% (for-each (lambda (g) %>
<article style="padding:24px 0;border-bottom:1px solid var(--rule)">
<div class="btn-row" style="justify-content:space-between;align-items:baseline">
<a href=<%= (qa (row-ref g "url")) %> rel="noopener nofollow" style="font-weight:600;word-break:break-all"><%= (h (row-ref g "url")) %></a>
<span class="small muted"><%= (plural (row-ref g "n") "reader" "readers") %> &middot; last <%= (h (row-ref g "last_date")) %></span>
</div>
<ul style="margin:10px 0 0;padding:0;list-style:none;display:flex;flex-direction:column;gap:6px;font-size:16px">
<% (for-each (lambda (n) %><li><span class="mention" style="font-weight:600">@<%= (h (assoc-ref n "handle")) %></span> <%= (h (assoc-ref n "note")) %></li><% ) (notes-of g)) %>
</ul>
<div class="btn-row" style="margin-top:14px">
<% (cond ((row-ref g "used") %><span class="pill on">used</span><% (when (row-ref g "slug") %> in <a href=<%= (qa "/posts/" (row-ref g "slug")) %>><%= (h (row-ref g "title")) %></a><% )) ((row-ref g "dismissed") %><span class="pill">set aside</span><% ) (else %>
<form method="post" action="/admin/inbox/use" class="btn-row">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>><input type="hidden" name="url_norm" value=<%= (qa (row-ref g "url_norm")) %>>
<label class="visually-hidden" for=<%= (qa "use-" (row-ref g "url_norm")) %>>Used in</label>
<select name="post_id" id=<%= (qa "use-" (row-ref g "url_norm")) %> style="width:auto;min-height:36px;font-size:15px"><option value="">Used in&hellip;</option><% (for-each (lambda (p) %><option value=<%= (qa (row-ref p "id")) %>><%= (h (excerpt (row-ref p "title") 60)) %></option><% ) posts) %></select>
<button class="btn small" type="submit">Mark used</button>
</form>
<form method="post" action="/admin/inbox/dismiss"><input type="hidden" name="csrf" value=<%= (qa csrf) %>><input type="hidden" name="url_norm" value=<%= (qa (row-ref g "url_norm")) %>><button class="btn plain small" type="submit">Set aside</button></form>
<a class="small" href=<%= (qa "/admin/new") %>>Write about it</a>
<% )) %>
</div>
</article>
<% ) groups) %>
<% (when (null? groups) %><p class="muted" style="margin-top:32px">Nothing waiting.</p><% ) %>
</main>
<@include admin/bottom.html.tpl %>
