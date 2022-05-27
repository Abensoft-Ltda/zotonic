<head>
	<meta charset="utf-8" />
	<title>{% block title %}{% endblock %} &mdash; {{ m.config.site.title.value }}</title>

	<!--
		Website built by:
		YOUR NAME HERE

		Proudly powered by: Zotonic, the Erlang CMS <http://www.zotonic.com>
	-->

	<meta name="viewport" content="width=device-width, initial-scale=1.0" />
	<meta name="author" content="YOUR NAME HERE &copy; 2014" />

	{% all include "_html_head.tpl" %}

	{% lib
		"bootstrap/css/bootstrap.min.css"
		"bootstrap/css/bootstrap-theme.min.css"
		"css/jquery.loadmask.css"
		"css/z-menu.css"
		"css/project.css"
	%}

	{% block html_head_extra %}{% endblock %}
</head>
