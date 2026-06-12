{%- from "salt_dependency_manager/macros.jinja" import dependency_from_pillar, config_for_side with context %}

{%- set raw_dependencies = salt['pillar.get']('salt_dependency_manager:dependencies', []) %}
{%- set dependencies = [] %}
{%- for entry in raw_dependencies %}
{%- do dependencies.append(dependency_from_pillar(entry)|load_yaml) %}
{%- endfor %}

{%- set local_dependencies = dependencies|selectattr('gitfs', 'equalto', False)|list %}
{%- set configured_sides = [] %}
{%- for dep in dependencies %}
{%- for side in dep.sides %}
{%- if side not in configured_sides %}
{%- do configured_sides.append(side) %}
{%- endif %}
{%- endfor %}
{%- endfor %}

{%- if not dependencies %}
salt_dependency_manager_no_dependencies:
  test.nop:
    - name: No salt_dependency_manager:dependencies pillar entries were found.
{%- else %}

{%- if local_dependencies %}
salt_dependency_manager_git:
  pkg.installed:
    - name: git

{%- set base_paths = [] %}
{%- for dep in local_dependencies %}
{%- if dep.path not in base_paths %}
{%- do base_paths.append(dep.path) %}
{{ dep.path }}:
  file.directory:
    - makedirs: True
    - user: root
    - group: root
    - require:
      - pkg: salt_dependency_manager_git

{%- endif %}
salt_dependency_manager_clone_{{ dep.id }}:
  git.latest:
    - name: {{ dep.url }}
    - target: {{ dep.root }}
    - rev: {{ dep.ref }}
{%- if not dep.update %}
    - unless: test -d {{ dep.root }}/.git
{%- endif %}
{%- for key, value in dep.options.items() %}
    - {{ key }}: {{ value|json }}
{%- endfor %}
    - require:
      - file: {{ dep.path }}

{%- endfor %}
{%- endif %}

{%- for side in configured_sides %}
{%- if side in ['master', 'minion'] %}
/etc/salt/{{ side }}.d:
  file.directory:
    - makedirs: True
    - user: root
    - group: root

/etc/salt/{{ side }}.d/salt-dependency-manager.conf:
  file.managed:
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
{{ config_for_side(side, dependencies)|indent(8, True) }}
    - require:
      - file: /etc/salt/{{ side }}.d
{%- for dep in local_dependencies if side in dep.sides %}
      - git: salt_dependency_manager_clone_{{ dep.id }}
{%- endfor %}

{%- else %}
salt_dependency_manager_invalid_side_{{ side }}:
  test.fail_without_changes:
    - name: "Invalid dependency side '{{ side }}'. Expected 'master' or 'minion'."
{%- endif %}
{%- endfor %}

{%- endif %}
