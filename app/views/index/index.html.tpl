<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<script type="application/ld+json"><%= extra-ld %></script>
</head>
<body>
<a class="skip" href="#content">Skip to the writing</a>
<div class="topline">
<div class="wrap">
<span>Written by a human</span>
<nav aria-label="Account">
<a href="#letter">Subscribe</a>
<a href="/signin" data-account>Sign in</a>
</nav>
</div>
</div>

<header class="masthead wrap">
<a class="title" href="/"><%= (h (site-name)) %></a>
<p class="tagline"><%= (h (site-tagline)) %></p>
<nav aria-label="Sections">
<a href="/archive">Archive</a>
<a href="/about">About</a>
<a href="/tags">Tags</a>
<a href="/principles">Principles</a>
<a href="/submit">Submit a link</a>
<a href="/feed/atom">Atom</a>
</nav>
</header>

<div class="wrap home">
<main id="content">
<% (if lead (begin %>
<article class="lead">
<div class="eyebrow"><%= (h (row-ref lead "date_long")) %><% (for-each (lambda (t) %> &middot; <%= (h t) %><% ) (row-ref lead "tags")) %></div>
<h1><a href=<%= (qa "/posts/" (row-ref lead "slug")) %>><%= (h (row-ref lead "title")) %></a></h1>
<% (when (present? (row-ref lead "dek")) %><p class="dek"><%= (h (row-ref lead "dek")) %></p><% ) %>
<div class="meta">
<a href=<%= (qa "/posts/" (row-ref lead "slug")) %>>Read it</a>
<span><%= (questions-phrase (row-ref lead "n_questions")) %></span>
</div>
</article>
<% (for-each (lambda (p) %>
<article class="entry">
<div class="date eyebrow"><%= (h (row-ref p "date_short")) %></div>
<div class="body">
<h2><a href=<%= (qa "/posts/" (row-ref p "slug")) %>><%= (h (row-ref p "title")) %></a></h2>
<% (when (present? (row-ref p "dek")) %><p><%= (h (row-ref p "dek")) %></p><% ) %>
<div class="meta"><% (for-each (lambda (t) %><a href=<%= (qa "/tags/" (url-encode t)) %>><%= (h t) %></a> &middot; <% ) (row-ref p "tags")) %><% (when (row-ref p "submitted_by_handle") %>sent in by @<%= (h (row-ref p "submitted_by_handle")) %> &middot; <% ) %><%= (questions-phrase (row-ref p "n_questions")) %></div>
</div>
</article>
<% ) rest) %>
<a class="more eyebrow" href="/archive">The full archive</a>
<% ) (begin %>
<p class="muted">Nothing is published yet.</p>
<% )) %>
</main>

<aside aria-label="About this site" class="side">
<section aria-labelledby="h-house">
<h2 id="h-house">The house rule</h2>
<p class="quote">Every sentence here was written by a person. Readers are asked to do the same.</p>
<a class="go" href="/principles">Read the principles</a>
</section>

<section id="letter" aria-labelledby="h-letter">
<h2 id="h-letter">The letter</h2>
<p>New writing by email. No account needed, one click to leave.</p>
<form method="post" action="/letter" class="field" style="margin-top:14px">
<label for="nl-email">Email address</label>
<input id="nl-email" name="email" type="email" autocomplete="email" required>
<div class="visually-hidden" aria-hidden="true"><label for="nl-website">Leave empty</label><input id="nl-website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
<button class="btn" type="submit">Subscribe</button>
</form>
</section>

<section aria-labelledby="h-submit">
<h2 id="h-submit">Send something in</h2>
<p>Found a paper or a post worth an opinion? Submit the link with a line on why. It may get a commentary, it may shape an essay, it may get nothing.</p>
<a class="go" href="/submit">Submit a link</a>
</section>

<@include shared/sponsor.html.tpl %>
</aside>
</div>

<@include shared/footer.html.tpl %>
</body>
</html>
