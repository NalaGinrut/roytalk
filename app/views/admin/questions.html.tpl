<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">Questions</h1>
<p class="muted small">Everything readers wrote, newest first. Delete hides a question from readers (Restore brings it back). Merge questions that ask the same thing; their askers are then listed together.</p>
<% (when merged-ok %><div class="notice" style="margin-top:18px"><p>Merged. Replies moved to the target question.</p></div><% ) %>
<% (when merge-error %><div class="notice error" style="margin-top:18px"><p>That merge was not possible: both questions must be visible, top-level, on the same piece, and not already merged.</p></div><% ) %>
<div class="scroll-x" style="margin-top:20px"><table class="table">
<thead><tr><th>When</th><th>Who</th><th>On</th><th>Text</th><th>Merge / moderate</th></tr></thead>
<tbody>
<% (for-each (lambda (i) %><tr<%= (if (row-ref i "hidden") " style=\"opacity:.55\"" "") %>>
<td class="small muted" style="white-space:nowrap"><%= (h (row-ref i "at")) %></td>
<td class="small">@<%= (h (row-ref i "handle")) %><% (when (row-ref i "banned") %> <span class="pill">banned</span><% ) %></td>
<td class="small"><a href=<%= (qa "/posts/" (row-ref i "slug") "#q-" (row-ref i "id")) %>><%= (h (excerpt (row-ref i "title") 40)) %></a><%= (if (row-ref i "parent_id") " (reply)" "") %><% (when (row-ref i "merged_into") %> <span class="muted">in</span> <a href=<%= (qa "/posts/" (row-ref i "slug") "#q-" (row-ref i "merged_into")) %>>#<%= (h (row-ref i "merged_into")) %></a><% ) %></td>
<td><% (when (present? (row-ref i "quote_exact")) %><div class="small muted" style="font-style:italic">&ldquo;<%= (h (excerpt (row-ref i "quote_exact") 90)) %>&rdquo;</div><% ) %><%= (h (excerpt (row-ref i "body") 220)) %></td>
<td>
<div class="admin-q-actions">
<% (when (row-ref i "merged_into") %>
<form method="post" action=<%= (qa "/admin/questions/" (row-ref i "id") "/unmerge") %>><input type="hidden" name="csrf" value=<%= (qa csrf) %>><button class="btn plain small" type="submit">Unmerge</button></form>
<% ) %>
<% (when (and (not (row-ref i "parent_id")) (not (row-ref i "merged_into")) (not (row-ref i "hidden")) (pair? (row-ref i "candidates"))) %>
<form method="post" class="merge-form" action=<%= (qa "/admin/questions/" (row-ref i "id") "/merge") %>>
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<select name="target" aria-label="Merge into">
<option value="">Merge into&hellip;</option>
<% (for-each (lambda (c) %><option value=<%= (qa (row-ref c "id")) %>>@<%= (h (row-ref c "handle")) %> &mdash; <%= (h (excerpt (or (row-ref c "quote_exact") (row-ref c "body")) 50)) %></option><% ) (row-ref i "candidates")) %>
</select>
<button class="btn plain small" type="submit">Merge</button>
</form>
<% ) %>
<% (when (> (row-ref i "n_merged") 0) %><div class="small muted"><%= (h (row-ref i "n_merged")) %> grouped</div><% ) %>
<form method="post" action=<%= (qa "/admin/questions/" (row-ref i "id") "/hide") %>><input type="hidden" name="csrf" value=<%= (qa csrf) %>><input type="hidden" name="hidden" value=<%= (qa (if (row-ref i "hidden") "0" "1")) %>><button class="btn plain small" type="submit"><%= (if (row-ref i "hidden") "Restore" "Delete") %></button></form>
</div>
</td>
</tr><% ) items) %>
</tbody></table></div>
<% (when (null? items) %><p class="muted">Nothing yet.</p><% ) %>
</main>
<@include admin/bottom.html.tpl %>
