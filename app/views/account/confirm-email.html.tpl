<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Sign in</div>
<% (if email (begin %>
<h1>One more step</h1>
<p class="standfirst">Continue as <%= (h email) %>.</p>
<form method="post" action=<%= (qa "/signin/email/" token) %> style="margin-top:32px">
<button class="btn" type="submit">Sign in</button>
</form>
<% ) (begin %>
<h1>This link has expired</h1>
<p class="standfirst">Sign-in links work once, for twenty minutes.</p>
<p style="margin-top:32px"><a class="btn" href="/signin">Get a new link</a></p>
<% )) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
