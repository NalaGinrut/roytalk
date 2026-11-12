<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">A question about</div>
<h1 style="font-size:52px"><a href=<%= (qa "/posts/" (row-ref post "slug")) %> style="color:inherit;text-decoration:none"><%= (h (row-ref post "title")) %></a></h1>
<p class="standfirst">Say what you doubt and why. Ask one question at a time; a post with several is easy to ignore. To question one sentence instead, select it in the essay.</p>
<% (when error-message %><div class="notice error" role="alert" style="margin-top:28px"><p><%= (h error-message) %></p></div><% ) %>
<form method="post" action=<%= (qa "/posts/" (row-ref post "slug") "/questions") %> class="field" style="margin-top:32px;max-width:640px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<label for="body">Your question</label>
<textarea id="body" name="body" required minlength="40" maxlength="6000"><%= (h body) %></textarea>
<p class="hint"><strong>One question at a time, please</strong> — ask other doubts separately so each one gets an answer. Public, under your handle. Your own words, please.</p>
<div class="btn-row"><button class="btn" type="submit">Post the question</button><a href=<%= (qa "/posts/" (row-ref post "slug")) %>>Back to the essay</a></div>
</form>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
