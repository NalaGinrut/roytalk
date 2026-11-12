<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">Readers</h1>
<p class="muted small"><%= (plural (length items) "account" "accounts") %>. A ban hides everything the reader wrote and signs them out.</p>
<div class="scroll-x" style="margin-top:20px"><table class="table">
<thead><tr><th>Handle</th><th>Since</th><th>Signs in with</th><th class="count">Questions</th><th class="count">Links</th><th></th></tr></thead>
<tbody>
<% (for-each (lambda (i) %><tr>
<td>@<%= (h (or (row-ref i "handle") "(no handle yet)")) %><% (when (row-ref i "is_author") %> <span class="pill on">author</span><% ) %><% (when (row-ref i "banned") %> <span class="pill">banned</span><% ) %></td>
<td class="small muted"><%= (h (row-ref i "since")) %></td>
<td class="small"><%= (h (row-ref i "via")) %></td>
<td class="count"><%= (row-ref i "n_q") %></td>
<td class="count"><%= (row-ref i "n_s") %></td>
<td><% (unless (row-ref i "is_author") %><form method="post" action=<%= (qa "/admin/readers/" (row-ref i "id") "/ban") %>><input type="hidden" name="csrf" value=<%= (qa csrf) %>><input type="hidden" name="banned" value=<%= (qa (if (row-ref i "banned") "0" "1")) %>><button class=<%= (qa "btn small " (if (row-ref i "banned") "plain" "danger")) %> type="submit"><%= (if (row-ref i "banned") "Lift ban" "Ban") %></button></form><% ) %></td>
</tr><% ) items) %>
</tbody></table></div>
</main>
<@include admin/bottom.html.tpl %>
