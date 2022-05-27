<body class="{% block page_class %}page{% endblock %}">

	<div class="navbar navbar-inverse navbar-fixed-top">

		<div class="container">
			<div class="navbar-header">
				<a class="navbar-brand" href="/">{{ m.site.title|default:"Your Zotonic Site" }} {% if m.site.subtitle %}{% endif %}</a>
				{# <span>{{ m.site.subtitle }}</span> #}
			</div>
			{% menu id=id %}
		</div>
	</div>
	<!-- end navbar -->

	<div class="container">

		<div class="row">
			{% block content_area %}
				{% block chapeau %}{% endblock %}

				<div class="col-lg-8 col-md-8">
					{% block content %}
						<!-- The default content goes here. -->
					{% endblock %}
					{% block below_body %}
						<!--
							The block 'below_body' is used by some modules to add
							content, it MUST be present to allow those modules to
							work properly.
							Example is 'mod_survey' which adds buttons for survey pages.
						-->
					{% endblock %}
				</div>

				<div id="sidebar" class="col-lg-4 col-md-4">
					{% block sidebar %}
						{% include "_sidebar.tpl" %}
					{% endblock %}
				</div>

			{% endblock %}

		</div>

		<div class="row">
			<div class="col-lg-12 col-md-12 clearfix" id="footer">
				<div class="pull-right">
					<p class="footer-blog-title">{% include "_powered_by_zotonic.tpl" %}</p>
				</div>
				{% menu id=id menu_id='footer_menu' %}
			</div>
		</div>
	</div>

	{% include "_js_include_jquery.tpl" %}
	{% lib
		"js/modules/jstz.min.js"
		"cotonic/cotonic.js"
		"bootstrap/js/bootstrap.min.js"
		"js/apps/zotonic-wired.js"
		"js/apps/z.widgetmanager.js"
		"js/modules/livevalidation-1.3.js"
		"js/modules/z.dialog.js"
		"js/modules/jquery.loadmask.js"
	%}

	{% block _js_include_extra %}{% endblock %}

	<script type="text/javascript" nonce="{{ m.req.csp_nonce }}">
		$(function() { $.widgetManager(); });
	</script>

	{% all include "_html_body.tpl" %}

	{% script %}

	{% worker name="auth" src="js/zotonic.auth.worker.js" args=%{  auth: m.authentication.status  } %}
</body>
