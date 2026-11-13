<@include admin/top.html.tpl %>
<main class="wrap" style="padding-top:32px;padding-bottom:80px">
<% (when error-message %><div class="notice error" role="alert" style="margin-bottom:24px"><p><%= (h error-message) %></p></div><% ) %>
<% (when (query-ref rc "saved") %><div class="notice" role="status" style="margin-bottom:24px"><p>Saved.<% (when (equal? (f "status") "published") %> <a href=<%= (qa "/posts/" (f "slug")) %>>See it on the site</a>.<% ) %></p></div><% ) %>
<form method="post" action=<%= (qa (if (present? (f "id")) (string-append "/admin/posts/" (f "id")) "/admin/posts")) %> class="editor" id="editor">
<input type="hidden" name="csrf" value=<%= (qa csrf) %>>
<div class="left">
<div class="field"><label for="title">Title</label><input id="title" name="title" type="text" required value=<%= (qa (f "title")) %>></div>
<div class="field"><label for="dek">Standfirst</label><input id="dek" name="dek" type="text" value=<%= (qa (f "dek")) %> maxlength="300"></div>
<div class="btn-row" style="align-items:flex-start">
<div class="field" style="flex:1 1 220px"><label for="slug">Address: /posts/&hellip;</label><input id="slug" name="slug" type="text" value=<%= (qa (f "slug")) %> placeholder="from the title"></div>
<div class="field" style="flex:1 1 220px"><label for="tags">Tags, comma separated</label><input id="tags" name="tags" type="text" value=<%= (qa tags-str) %>></div>
</div>
<details <%= (if (or (present? (f "source_url")) (present? submitted)) "open" "") %>>
<summary class="label-muted" style="cursor:pointer">Commentary on an outside piece</summary>
<div class="btn-row" style="align-items:flex-start;margin-top:12px">
<div class="field" style="flex:1 1 260px"><label for="source_url">Source link</label><input id="source_url" name="source_url" type="url" value=<%= (qa (f "source_url")) %>></div>
<div class="field" style="flex:1 1 200px"><label for="source_title">Source title</label><input id="source_title" name="source_title" type="text" value=<%= (qa (f "source_title")) %>></div>
<div class="field" style="flex:0 1 160px"><label for="submitted_by">Sent in by</label><input id="submitted_by" name="submitted_by" type="text" value=<%= (qa submitted) %> placeholder="@handle"></div>
</div>
</details>
<div class="field"><label for="body_md">Markdown</label><textarea id="body_md" name="body_md" class="md" spellcheck="true"><%= (h (f "body_md")) %></textarea>
<p class="hint">GitHub-flavoured Markdown. <code>$x$</code> and <code>$$x$$</code> for math. Fence code with a language (<code>```llvm</code>, <code>```asm</code>, <code>```c</code>, <code>```scheme</code>) for highlighting. Rendered once, when you save.</p></div>
<div class="btn-row">
<button class="btn plain" type="submit" name="action" value="save">Save</button>
<% (if (equal? (f "status") "published") (begin %><button class="btn plain" type="submit" name="action" value="unpublish">Unpublish</button><button class="btn" type="submit" name="action" value="save">Update</button><% ) (begin %><button class="btn" type="submit" name="action" value="publish">Publish</button><% )) %>
</div>
</div>
<div class="right">
<div class="btn-row" style="justify-content:space-between;margin-bottom:10px"><span class="label-muted">Preview</span><button type="button" class="btn plain small" data-preview>Refresh preview</button></div>
<div class="preview"><div class="prose" id="preview"><%= (f "body_html") %></div></div>
</div>
</form>
<% (when (present? (f "id")) %>
<div class="btn-row" style="margin-top:40px;padding-top:24px;border-top:1px solid var(--rule)">
<% (when (and (equal? (f "status") "published") (blank? (f "emailed"))) %><span class="muted small">This piece joins the next monthly digest.</span><% ) %>
<% (when (present? (f "emailed")) %><span class="muted small">Included in the monthly letter on <%= (h (f "emailed")) %>.</span><% ) %>
<% (when (equal? (f "status") "draft") %><form method="post" action=<%= (qa "/admin/posts/" (f "id") "/delete") %>><input type="hidden" name="csrf" value=<%= (qa csrf) %>><button class="btn danger" type="submit" data-confirm="Delete this draft for good?">Delete draft</button></form><% ) %>
</div>
<% ) %>
</main>
<@include admin/bottom.html.tpl %>
