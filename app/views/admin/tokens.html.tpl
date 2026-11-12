<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px;max-width:820px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">API tokens</h1>
<p class="muted small">For your own tools. Read-only: <code>GET /api/v1/submissions</code> and <code>GET /api/v1/questions</code>, with <code>Authorization: Bearer &lt;token&gt;</code> and an optional <code>?since=</code> timestamp.</p>
<% (when fresh %><div class="notice" role="status" style="margin-top:24px"><p>Copy it now; it will not be shown again.</p><p class="token-once" style="margin-top:10px"><%= (h fresh) %></p></div><% ) %>
<form method="post" action="/admin/tokens" class="btn-row" style="margin-top:28px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<label class="visually-hidden" for="tname">Name</label>
<input id="tname" name="name" type="text" placeholder="What it is for" style="flex:1 1 260px;width:auto">
<button class="btn" type="submit">Create a token</button>
</form>
<table class="table" style="margin-top:28px">
<thead><tr><th>Name</th><th>Created</th><th>Last used</th><th></th></tr></thead>
<tbody>
<% (for-each (lambda (t) %><tr<%= (if (row-ref t "revoked") " style=\"opacity:.55\"" "") %>>
<td><%= (h (row-ref t "name")) %></td><td class="small"><%= (h (row-ref t "created")) %></td><td class="small"><%= (h (or (row-ref t "used") "never")) %></td>
<td><% (if (row-ref t "revoked") (begin %><span class="pill">revoked</span><% ) (begin %><form method="post" action=<%= (qa "/admin/tokens/" (row-ref t "id") "/revoke") %>><input type="hidden" name="csrf" value=<%= (qa csrf) %>><button class="btn danger small" type="submit" data-confirm="Revoke this token?">Revoke</button></form><% )) %></td>
</tr><% ) tokens) %>
</tbody></table>
</main>
<@include admin/bottom.html.tpl %>
