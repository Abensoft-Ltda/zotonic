{% include "_admin_edit_floating_buttons.tpl" %}

<div> {# also sidebar #}
    {% include "_admin_edit_content_publish.tpl" headline="simple" %}

    {% include "_admin_edit_content_note.tpl" %}

    {% if id.is_a.meta %}
        {% include "_admin_edit_meta_features.tpl" %}
    {% endif %}

    {% include "_admin_edit_content_acl.tpl" %}

    {% if not id.is_a.meta %}
        {% include "_admin_edit_content_pub_period.tpl" %}
        {% include "_admin_edit_content_date_range.tpl" show_header %}
        {% optional include "_admin_edit_content_timezone.tpl" %}
    {% endif %}

    {% all catinclude "_admin_edit_sidebar.tpl" id languages=languages %}

    {% include "_admin_edit_content_page_connections.tpl" %}
    {% include "_admin_edit_content_page_referrers.tpl"%}
</div>
