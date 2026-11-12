<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px">
<div class="btn-row" style="justify-content:space-between">
<h1 class="page" style="padding:0;margin:0;font-family:var(--display);font-weight:500;font-size:52px">Writing</h1>
<a class="btn" href="/admin/new">New piece</a>
</div>
<p class="muted small" style="margin-top:12px"><a href="/admin/inbox"><%= (plural new-links "new link" "new links") %></a> in the inbox &middot; <a href="/admin/questions"><%= (plural new-questions "question or reply" "questions and replies") %></a> this week &middot; <a href="/admin/letter"><%= (plural subscribers "subscriber" "subscribers") %></a></p>
<div class="scroll-x" style="margin-top:28px"><table class="table">
<thead><tr><th>Title</th><th>State</th><th>Tags</th><th class="count">Reads</th><th class="count">Questions</th><th>Letter</th></tr></thead>
<tbody>
<% (for-each (lambda (p) %><tr>
<td><a href=<%= (qa "/admin/posts/" (row-ref p "id")) %> style="font-weight:600"><%= (h (row-ref p "title")) %></a><div class="small muted">/posts/<%= (h (row-ref p "slug")) %> &middot; edited <%= (h (row-ref p "updated_short")) %></div></td>
<td><% (if (equal? (row-ref p "status") "published") (begin %><span class="pill on">published</span> <span class="small muted"><%= (h (row-ref p "date_long")) %></span><% ) (begin %><span class="pill">draft</span><% )) %></td>
<td class="small"><%= (h (string-join (row-ref p "tags") ", ")) %></td>
<td class="count"><%= (row-ref p "views") %></td>
<td class="count"><%= (row-ref p "n_questions") %></td>
<td class="small"><%= (h (or (row-ref p "emailed") "")) %></td>
</tr><% ) posts) %>
</tbody></table></div>
<% (when (null? posts) %><p class="muted">Nothing yet. <a href="/admin/new">Write the first piece.</a></p><% ) %>
</main>
<@include admin/bottom.html.tpl %>
