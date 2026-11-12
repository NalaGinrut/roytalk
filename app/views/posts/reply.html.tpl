<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">A reply, on <a href=<%= (qa "/posts/" (row-ref target "slug")) %>><%= (h (row-ref target "title")) %></a></div>
<div style="margin-top:28px;max-width:640px">
<% (when (present? (row-ref target "quote_exact")) %><blockquote class="q-quote"><%= (h (row-ref target "quote_exact")) %></blockquote><% ) %>
<div class="who-line" style="margin-top:12px"><span class="handle">@<%= (h (row-ref target "handle")) %></span> wrote</div>
<div class="said-body"><%= (paragraphs->html (row-ref target "body")) %></div>
</div>
<% (when error-message %><div class="notice error" role="alert" style="margin-top:28px"><p><%= (h error-message) %></p></div><% ) %>
<form method="post" action=<%= (qa "/questions/" (row-ref target "id") "/replies") %> class="field" style="margin-top:32px;max-width:640px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<label for="body">Your reply to @<%= (h (row-ref target "handle")) %></label>
<textarea id="body" name="body" required minlength="8" maxlength="6000"><%= (h body) %></textarea>
<p class="hint">Public, under your handle. Your own words, please.</p>
<div class="btn-row"><button class="btn" type="submit">Post the reply</button><a href=<%= (qa "/posts/" (row-ref target "slug") "#q-" (row-ref target "id")) %>>Back to the thread</a></div>
</form>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
