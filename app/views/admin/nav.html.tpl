<nav class="admin-nav wrap" aria-label="Desk">
<a href="/admin" class=<%= (qa (if (equal? section "posts") "on" "")) %>>Writing</a>
<a href="/admin/inbox" class=<%= (qa (if (equal? section "inbox") "on" "")) %>>Inbox</a>
<a href="/admin/questions" class=<%= (qa (if (equal? section "questions") "on" "")) %>>Questions</a>
<a href="/admin/readers" class=<%= (qa (if (equal? section "readers") "on" "")) %>>Readers</a>
<a href="/admin/tags" class=<%= (qa (if (equal? section "tags") "on" "")) %>>Tags</a>
<a href="/admin/sponsors" class=<%= (qa (if (equal? section "sponsors") "on" "")) %>>Sponsors</a>
<a href="/admin/letter" class=<%= (qa (if (equal? section "letter") "on" "")) %>>Letter</a>
<a href="/admin/tokens" class=<%= (qa (if (equal? section "tokens") "on" "")) %>>API</a>
</nav>
