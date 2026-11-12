<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow"><%= (if standfirst "Tag" "Everything, newest first") %></div>
<h1><%= (h heading) %></h1>
<% (when standfirst %><p class="standfirst"><%= (h standfirst) %></p><% ) %>
<% (for-each (lambda (group) %>
<section class="year">
<% (when (car group) %><h2><%= (h (car group)) %></h2><% ) %>
<% (for-each (lambda (p) %>
<article class="entry">
<div class="date eyebrow"><%= (h (row-ref p "date_short")) %></div>
<div class="body">
<h2><a href=<%= (qa "/posts/" (row-ref p "slug")) %>><%= (h (row-ref p "title")) %></a></h2>
<% (when (present? (row-ref p "dek")) %><p><%= (h (row-ref p "dek")) %></p><% ) %>
<div class="meta"><% (for-each (lambda (t) %><a href=<%= (qa "/tags/" (url-encode t)) %>><%= (h t) %></a> &middot; <% ) (row-ref p "tags")) %><%= (questions-phrase (row-ref p "n_questions")) %></div>
</div>
</article>
<% ) (cdr group)) %>
</section>
<% ) years) %>
<% (when (null? years) %><p class="muted">Nothing is published yet.</p><% ) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
