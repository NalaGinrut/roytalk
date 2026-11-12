<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow"><a href="/me">Your account</a></div>
<h1>Your questions</h1>
<% (if (null? items) (begin %><p class="standfirst">None yet. Select a sentence in any essay to question it.</p><% ) (begin %>
<div class="scroll-x" style="margin-top:40px"><table class="table">
<thead><tr><th>When</th><th>On</th><th>What you wrote</th></tr></thead>
<tbody>
<% (for-each (lambda (i) %><tr>
<td class="small muted" style="white-space:nowrap"><%= (h (row-ref i "date_long")) %></td>
<td><a href=<%= (qa "/posts/" (row-ref i "slug") "#q-" (row-ref i "link_id")) %>><%= (h (row-ref i "title")) %></a><% (when (row-ref i "parent_id") %> <span class="muted small">(reply)</span><% ) %><% (when (row-ref i "merged") %> <span class="pill">grouped</span><% ) %><% (when (row-ref i "hidden") %> <span class="pill">hidden</span><% ) %></td>
<td><%= (h (excerpt (row-ref i "body") 160)) %></td>
</tr><% ) items) %>
</tbody></table></div>
<% )) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
