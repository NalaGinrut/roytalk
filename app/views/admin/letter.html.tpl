<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:40px;padding-bottom:80px;max-width:820px">
<h1 style="margin:0;font-family:var(--display);font-weight:500;font-size:52px">The letter</h1>
<p class="muted small">Subscribers are a separate list from accounts.</p>
<table class="table" style="margin-top:24px;max-width:420px">
<tbody>
<% (for-each (lambda (c) %><tr><td><%= (h (row-ref c "status")) %></td><td class="count"><%= (row-ref c "n") %></td></tr><% ) counts) %>
</tbody></table>
<h2 class="eyebrow" style="margin-top:40px">Monthly digest</h2>
<p>One digest goes out on the first of each month, with the pieces published since the last digest and a link to read each one on the site. With nothing new, nothing is sent.</p>
<% (if digest %><p class="small muted">Last digest: <%= (h (row-ref digest "sent")) %> &middot; <%= (plural (row-ref digest "post_count") "piece" "pieces") %> to <%= (plural (row-ref digest "recipient_count") "subscriber" "subscribers") %>.</p><% ) %>
<h2 class="eyebrow" style="margin-top:40px">Outgoing mail</h2>
<p><%= (row-ref outbox "pending") %> waiting, <%= (row-ref outbox "failing") %> retrying, <%= (row-ref outbox "sent_today") %> sent in the last day.</p>
<p class="hint">tools/mailer.scm sends the queue. If mail is waiting and nothing is sent, check that the mailer service is running.</p>
</main>
<@include admin/bottom.html.tpl %>
