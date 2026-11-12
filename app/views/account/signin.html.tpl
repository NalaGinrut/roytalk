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
<h1>Sign in</h1>
<p class="standfirst">To ask a question or send in a link. There is no password: choose an account you already have, or get a one-time link by email.</p>
<% (when error-message %><div class="notice error" role="alert" style="margin-top:28px;max-width:640px"><p><%= (h error-message) %></p></div><% ) %>
<div style="margin-top:40px;max-width:420px;display:flex;flex-direction:column;gap:12px">
<% (for-each (lambda (p) %><a class="btn plain" href=<%= (qa "/auth/" p "?next=" (url-encode next)) %>>Continue with <%= (h (provider-label p)) %></a><% ) providers) %>
</div>
<form method="post" action="/signin/email" class="field" style="margin-top:40px;max-width:420px;padding-top:28px;border-top:1px solid var(--rule)">
<input type="hidden" name="next" value=<%= (qa next) %>>
<label for="email">Or by email</label>
<input id="email" name="email" type="email" autocomplete="email" required>
<div class="visually-hidden" aria-hidden="true"><label for="website">Leave empty</label><input id="website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
<button class="btn" type="submit">Email me a sign-in link</button>
<p class="hint">We keep the address you sign in with and the handle you choose. Nothing else. See the <a href="/principles">principles</a>.</p>
</form>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
