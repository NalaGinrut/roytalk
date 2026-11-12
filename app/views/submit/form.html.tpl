<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Send something in</div>
<h1>Submit a link</h1>
<p class="standfirst">A paper, a post, a talk, a patch. Say why it matters or what you want to know about it.</p>
<div class="body-col" style="margin-top:28px">
<p class="muted">I read everything that comes in. I may write a commentary on it, fold it into an essay, or leave it. If I use it, I may say so in the piece. The list of submissions is not public.</p>
</div>
<% (when done? %><div class="notice" role="status" style="margin-top:28px;max-width:640px"><p>Received, thank you. You can follow it under <a href="/me/submissions">your links</a>.</p></div><% ) %>
<% (when error-message %><div class="notice error" role="alert" style="margin-top:28px;max-width:640px"><p><%= (h error-message) %></p></div><% ) %>
<% (if acc (begin %>
<form method="post" action="/submit" style="margin-top:32px;max-width:640px;display:flex;flex-direction:column;gap:22px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<div class="field"><label for="url">Link</label><input id="url" name="url" type="url" required value=<%= (qa url) %> placeholder="https://"></div>
<div class="field"><label for="note">Why it is worth an opinion</label><textarea id="note" name="note" required minlength="20" maxlength="2000"><%= (h note) %></textarea></div>
<div><button class="btn" type="submit">Send it in</button></div>
</form>
<% ) (begin %>
<p style="margin-top:32px"><a class="btn" href="/signin?next=/submit">Sign in to submit</a></p>
<% )) %>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
