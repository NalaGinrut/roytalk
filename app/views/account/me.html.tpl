<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Your account</div>
<h1>@<%= (h (account-handle acc)) %></h1>
<% (when notice %><div class="notice" role="status" style="margin-top:28px;max-width:640px"><p><%= (h notice) %></p></div><% ) %>

<section class="split" aria-labelledby="h-yours">
<h2 id="h-yours">What you wrote</h2>
<div>
<p><a href="/me/questions"><%= (plural n-questions "question or reply" "questions and replies") %></a></p>
<p><a href="/me/submissions"><%= (plural n-submissions "link sent in" "links sent in") %></a></p>
<% (when (author? acc) %><p><a href="/admin">The author's desk</a></p><% ) %>
</div>
</section>

<section class="split" aria-labelledby="h-signin">
<h2 id="h-signin">Ways to sign in</h2>
<div>
<ul style="margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px">
<% (for-each (lambda (i) %><li><strong><%= (h (provider-label (row-ref i "provider"))) %></strong><% (when (row-ref i "email") %> &middot; <%= (h (row-ref i "email")) %><% ) %> <span class="muted small">since <%= (h (row-ref i "since")) %></span></li><% ) identities) %>
</ul>
<% (unless (null? linkable) %>
<p class="label-muted" style="margin-top:24px">Add another</p>
<div class="btn-row" style="margin-top:10px"><% (for-each (lambda (p) %><a class="btn plain small" href=<%= (qa "/auth/" p "/link") %>><%= (h (provider-label p)) %></a><% ) linkable) %></div>
<% ) %>
<% (unless (member "email" have) %>
<form method="post" action="/me/email" class="field" style="margin-top:24px;max-width:420px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<label for="email">Add an email address</label>
<input id="email" name="email" type="email" autocomplete="email" required>
<button class="btn plain small" type="submit">Send a link to confirm it</button>
</form>
<% ) %>
<p class="hint" style="margin-top:16px">GitHub, Google and email sign-ins with the same verified address join this account by themselves. X does not share addresses, so add it here.</p>
</div>
</section>

<section class="split" aria-labelledby="h-letter">
<h2 id="h-letter">The letter</h2>
<div>
<p>The newsletter is a separate list and does not use this account. Every letter has a one-click link to leave.</p>
</div>
</section>

<form method="post" action="/signout" style="margin-top:56px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<button class="btn plain" type="submit">Sign out</button>
</form>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
