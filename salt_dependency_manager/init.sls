{%- from "salt_dependency_manager/macros.jinja" import dependency_from_pillar, manage_dependencies with context %}

{%- set raw_dependencies = salt['pillar.get']('salt_dependency_manager:dependencies', []) %}
{%- set dependencies = [] %}
{%- for entry in raw_dependencies %}
{%- do dependencies.append(dependency_from_pillar(entry)|load_yaml) %}
{%- endfor %}

{{ manage_dependencies(dependencies) }}
