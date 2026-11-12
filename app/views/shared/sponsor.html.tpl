<% (when sponsor %><section class=<%= (qa "sponsor" sponsor-class) %> aria-labelledby="h-sponsor">
<h2 id="h-sponsor" class="eyebrow">Sponsor</h2>
<p><% (if (present? (row-ref sponsor "url")) (begin %><a href=<%= (qa (row-ref sponsor "url")) %> rel="sponsored noopener"><%= (h (row-ref sponsor "name")) %></a><% ) (begin %><%= (h (row-ref sponsor "name")) %><% )) %> &mdash; <%= (h (row-ref sponsor "line")) %></p>
</section><% ) %>
