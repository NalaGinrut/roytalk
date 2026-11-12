<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Index</div>
<h1>Tags</h1>
<p class="standfirst">The subjects meet more often than they part. Most pieces carry more than one.</p>
<ul class="tags-cloud">
<% (for-each (lambda (t) %><li><a href=<%= (qa "/tags/" (url-encode (row-ref t "name"))) %>><%= (h (row-ref t "name")) %></a> <span class="muted small count"><%= (row-ref t "n") %></span></li><% ) tags) %>
</ul>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
