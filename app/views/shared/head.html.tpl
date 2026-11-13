<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><%= (h page-title) %></title>
<meta name="description" content=<%= (qa page-desc) %>>
<meta name="author" content=<%= (qa (author-name)) %>>
<link rel="canonical" href=<%= (qa canonical) %>>
<link rel="alternate" type="application/atom+xml" title=<%= (qa (site-name)) %> href="/feed/atom">
<link rel="icon" href="/img/favicon.ico" sizes="any">
<link rel="icon" href="/img/favicon.svg" type="image/svg+xml">
<meta property="og:site_name" content=<%= (qa (site-name)) %>>
<meta property="og:title" content=<%= (qa page-title) %>>
<meta property="og:description" content=<%= (qa page-desc) %>>
<meta property="og:url" content=<%= (qa canonical) %>>
<meta property="og:image" content=<%= (qa (absolute-url "/img/og-default.webp")) %>>
<meta property="og:image:type" content="image/webp">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content=<%= (qa (site-name)) %>>
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content=<%= (qa (absolute-url "/img/og-default.webp")) %>>
<link rel="preload" href="/fonts/source-serif-4-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/fonts/cormorant-garamond-latin-500-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/css/fonts.css">
<link rel="stylesheet" href="/css/site.css">
