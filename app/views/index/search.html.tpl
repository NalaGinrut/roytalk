<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Search</div>
<h1>Search</h1>
<form method="get" action="/search" role="search" class="btn-row" style="margin-top:32px">
<label class="visually-hidden" for="q">Search the writing</label>
<input id="q" name="q" type="search" value=<%= (qa terms) %> style="flex:1 1 320px">
<button class="btn" type="submit">Search</button>
</form>
<% (cond ((string-null? terms) #t) ((null? results) %><p class="muted" style="margin-top:32px">Nothing matches &ldquo;<%= (h terms) %>&rdquo;.</p><% ) (else %>
<p class="muted small" style="margin-top:32px"><%= (plural (length results) "result" "results") %></p>
<% (for-each (lambda (p) %>
<article class="entry">
<div class="date eyebrow"><%= (h (row-ref p "date_short")) %></div>
<div class="body">
<h2><a href=<%= (qa "/posts/" (row-ref p "slug")) %>><%= (h (row-ref p "title")) %></a></h2>
<p><%= (search-snippet (row-ref p "snippet")) %></p>
</div>
</article>
<% ) results) %>
<% )) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
