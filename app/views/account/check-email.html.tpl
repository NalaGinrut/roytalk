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
<h1>Check your email</h1>
<p class="standfirst">If <%= (h email) %> can receive mail, a sign-in link is on its way. It works once, for twenty minutes.</p>
<p style="margin-top:32px" class="muted">Nothing arrived after a few minutes? Look in the spam folder, or <a href="/signin">try again</a>.</p>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
