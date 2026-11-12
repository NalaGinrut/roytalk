<footer class="footer">
<div class="wrap">
<span class="colophon">Served as plain HTML by <a href="https://artanis.dev">GNU Artanis</a>. No trackers, no passwords. We keep a sign-in and a handle, nothing else.</span>
<nav aria-label="Footer">
<a href="/principles">Principles</a>
<a href="/search">Search</a>
<% (when (present? (setting 'source-url #f)) %><a href=<%= (qa (setting 'source-url #f)) %>>Source code</a><% ) %>
<a href="/feed/atom">Atom feed</a>
</nav>
</div>
</footer>
<script src="/js/site.js" defer></script>
