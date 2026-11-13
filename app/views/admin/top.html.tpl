<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><%= (h page-title) %> · Desk</title>
<link rel="icon" href="/img/favicon.ico" sizes="any">
<link rel="icon" href="/img/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/css/fonts.css">
<link rel="stylesheet" href="/css/site.css">
</head>
<body>
<header class="bar"><div class="wrap"><a class="title" href="/">&larr; <%= (h (site-name)) %></a><nav><a href="/me">@<%= (h (account-handle acc)) %></a></nav></div></header>
<@include admin/nav.html.tpl %>
