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
<h1>Links you sent in</h1>
<p class="standfirst">Each one is read. Some become a commentary or part of an essay; some do not.</p>
<% (if (null? items) (begin %><p style="margin-top:32px"><a class="btn" href="/submit">Submit a link</a></p><% ) (begin %>
<div class="scroll-x" style="margin-top:40px"><table class="table">
<thead><tr><th>Sent</th><th>Link</th><th>Status</th></tr></thead>
<tbody>
<% (for-each (lambda (i) %><tr>
<td class="small muted" style="white-space:nowrap"><%= (h (row-ref i "date_long")) %></td>
<td><a href=<%= (qa (row-ref i "url")) %> rel="noopener nofollow"><%= (h (excerpt (row-ref i "url") 70)) %></a><div class="small muted"><%= (h (excerpt (row-ref i "note") 140)) %></div></td>
<td><% (if (and (equal? (row-ref i "status") "used") (row-ref i "slug")) (begin %><span class="pill on">used</span> in <a href=<%= (qa "/posts/" (row-ref i "slug")) %>><%= (h (row-ref i "title")) %></a><% ) (begin %><span class="pill">received</span><% )) %></td>
</tr><% ) items) %>
</tbody></table></div>
<p style="margin-top:28px"><a href="/submit">Submit another</a></p>
<% )) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
