<!doctype html>
<html lang="en">
<head>
<@include shared/head.html.tpl %>
<meta property="og:type" content="article">
<script type="application/ld+json"><%= extra-ld %></script>
</head>
<body>
<@include shared/bar.html.tpl %>

<div class="wrap article-head">
<div class="inner">
<div class="eyebrow"><% (for-each (lambda (t i) (unless (zero? i) %> &middot; <% ) %><a href=<%= (qa "/tags/" (url-encode t)) %> style="color:inherit;text-decoration:none"><%= (h t) %></a><% ) (row-ref post "tags") (iota (length (row-ref post "tags")))) %></div>
<h1><%= (h (row-ref post "title")) %></h1>
<% (when (present? (row-ref post "dek")) %><p class="dek"><%= (h (row-ref post "dek")) %></p><% ) %>
<% (when (present? (row-ref post "source_url")) %><p class="source">On <a href=<%= (qa (row-ref post "source_url")) %> rel="noopener"><%= (h (if (present? (row-ref post "source_title")) (row-ref post "source_title") (row-ref post "source_url"))) %></a><% (when (row-ref post "submitted_by_handle") %>, sent in by <span class="mention">@<%= (h (row-ref post "submitted_by_handle")) %></span><% ) %></p><% ) %>
</div>
<div class="byline">
<span>By <a class="who" href="/about"><%= (h (author-name)) %></a></span>
<time datetime=<%= (qa (row-ref post "date_iso")) %>><%= (h (row-ref post "date_long")) %></time>
<% (when (> views 0) %><span><%= (plural views "read" "reads") %></span><% ) %>
<a href="#questions"><%= (questions-phrase (length questions)) %></a>
</div>
</div>

<div class="wrap article-grid">
<% (when (present? (row-ref post "toc_html")) %>
<nav class="toc" aria-label="Contents">
<div class="eyebrow">Contents</div>
<%= (row-ref post "toc_html") %>
</nav>
<% ) %>

<div class="article-col">
<article id="content" class="prose" data-slug=<%= (qa (row-ref post "slug")) %>>
<%= (row-ref post "body_html") %>
</article>

<@include shared/sponsor.html.tpl %>

<section id="questions" class="questions" aria-labelledby="h-questions">
<h2 id="h-questions">Questions</h2>
<p class="intro">There is no applause here. Select any sentence above to question it. Hover or tap a questioned sentence to read the newest questions on it; every question is also listed below. Written by people; see the <a href="/principles">principles</a>.</p>

<% (for-each (lambda (q) %>
<article class="q" id=<%= (qa "q-" (row-ref q "id")) %> data-askers=<%= (qa (row-ref q "askers")) %> data-quote=<%= (qa (row-ref q "quote_exact")) %> data-prefix=<%= (qa (row-ref q "quote_prefix")) %> data-suffix=<%= (qa (row-ref q "quote_suffix")) %>>
<% (when (present? (row-ref q "quote_exact")) %><blockquote class=<%= (qa "q-quote" (if (stale? q) " stale" "")) %>><%= (h (row-ref q "quote_exact")) %></blockquote><% ) %>
<div>
<div class="who-line"><span class="handle">@<%= (h (row-ref q "handle")) %></span><% (when (row-ref q "is_author") %><span class="role">Author</span><% ) %><time datetime=<%= (qa (row-ref q "date_iso")) %>><%= (h (row-ref q "date_long")) %></time><a href=<%= (qa "#q-" (row-ref q "id")) %>>permalink</a></div>
<div class="said-body"><%= (paragraphs->html (row-ref q "body")) %></div>
<% (when (pair? (row-ref q "other_askers")) %><p class="also-asked"><%= (also-asked (row-ref q "other_askers")) %></p><% ) %>
</div>
<div class="replies">
<% (for-each (lambda (r) %>
<div class=<%= (qa "reply" (if (row-ref r "is_author") " by-author" "")) %> id=<%= (qa "q-" (row-ref r "id")) %>>
<div class="who-line"><span class="handle">@<%= (h (row-ref r "handle")) %></span><% (when (row-ref r "is_author") %><span class="role">Author</span><% ) %><time datetime=<%= (qa (row-ref r "date_iso")) %>><%= (h (row-ref r "date_long")) %></time><% (when (row-ref r "reply_to_handle") %><span>to @<%= (h (row-ref r "reply_to_handle")) %></span><% ) %><a href=<%= (qa "/questions/" (row-ref r "id") "/reply") %>>reply</a></div>
<div class="said-body"><%= (paragraphs->html (row-ref r "body")) %></div>
</div>
<% ) (row-ref q "replies")) %>
<% (when (null? (row-ref q "replies")) %><p class="hidden-note">No reply yet.</p><% ) %>
<a class="small" href=<%= (qa "/questions/" (row-ref q "id") "/reply") %> style="font-weight:600">Reply</a>
</div>
</article>
<% ) questions) %>

<div class="ask-whole">
<p>A question about the essay as a whole?</p>
<a class="btn outline" href=<%= (qa "/posts/" (row-ref post "slug") "/ask") %>>Ask it</a>
</div>
</section>
</div>
</div>

<template id="ask-template">
<form method="post" class="ask-pop" action=<%= (qa "/posts/" (row-ref post "slug") "/questions") %>>
<button type="button" class="close" aria-label="Close" data-close><svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 3l10 10M13 3L3 13"></path></svg></button>
<p class="lede">See it differently?</p>
<div data-signed-out>
<a class="btn" data-signin href="/signin">Sign in to question it</a>
<p class="hint" style="margin-top:10px">Your selection is kept while you sign in.</p>
</div>
<div data-signed-in hidden>
<input type="hidden" name="csrf" value="">
<input type="hidden" name="quote_exact" value="">
<input type="hidden" name="quote_prefix" value="">
<input type="hidden" name="quote_suffix" value="">
<label class="visually-hidden" for="ask-body">Your question</label>
<textarea id="ask-body" name="body" required minlength="8" maxlength="6000" placeholder="What do you doubt, and why?"></textarea>
<button class="btn" type="submit" style="margin-top:10px">Post the question</button>
<p class="hint" style="margin-top:8px"><strong>One question at a time, please</strong> — a post with several is easy to ignore. Public, under your handle. Your own words, please.</p>
</div>
</form>
</template>

<@include shared/footer.html.tpl %>
</body>
</html>
