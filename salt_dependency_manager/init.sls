{%- from "salt_dependency_manager/macros.jinja" import render_manager with context %}
{%- set config = salt['pillar.get']('salt_dependency_manager', none) %}

{{ render_manager(config) }}
