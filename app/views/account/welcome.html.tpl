<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta name="robots" content="noindex">
</head>
<body>
<@include shared/bar.html.tpl %>
<main id="content" class="narrow page">
<div class="eyebrow">Welcome</div>
<h1>Choose a handle</h1>
<p class="standfirst">It is the only thing other readers will see of you, and people can mention you with it. It cannot be changed later.</p>
<% (when error-message %><div class="notice error" role="alert" style="margin-top:28px;max-width:640px"><p><%= (h error-message) %></p></div><% ) %>
<form method="post" action="/welcome" class="field" style="margin-top:32px;max-width:420px">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<input type="hidden" name="next" value=<%= (qa next) %>>
<label for="handle">Handle</label>
<div class="btn-row" style="gap:6px;flex-wrap:nowrap"><span aria-hidden="true" style="font-size:20px">@</span><input id="handle" name="handle" type="text" value=<%= (qa handle) %> required pattern="[A-Za-z][A-Za-z0-9_]{1,23}" maxlength="24" autocomplete="username" autocapitalize="off" spellcheck="false"></div>
<p class="hint">2 to 24 characters: letters, digits and underscores, starting with a letter.</p>
<button class="btn" type="submit">Continue</button>
</form>
</main>
<@include shared/footer.html.tpl %>
</body>
</html>
