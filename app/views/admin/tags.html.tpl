<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px;max-width:820px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">Tags</h1>
<p class="muted small">Tags are added from the editor. Rename here; a tag no piece uses can be deleted.</p>
<% (for-each (lambda (t) %>
<form method="post" action=<%= (qa "/admin/tags/" (row-ref t "id")) %> class="btn-row" style="padding:12px 0;border-bottom:1px solid var(--rule)">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<label class="visually-hidden" for=<%= (qa "tag-" (row-ref t "id")) %>>Name</label>
<input id=<%= (qa "tag-" (row-ref t "id")) %> name="name" type="text" value=<%= (qa (row-ref t "name")) %> style="flex:1 1 220px;width:auto">
<span class="small muted count" style="min-width:70px"><%= (plural (row-ref t "n") "piece" "pieces") %></span>
<button class="btn plain small" type="submit" name="action" value="rename">Rename</button>
<% (when (zero? (row-ref t "n")) %><button class="btn danger small" type="submit" name="action" value="delete">Delete</button><% ) %>
</form>
<% ) tags) %>
</main>
<@include admin/bottom.html.tpl %>
