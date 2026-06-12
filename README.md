# salt-dependency-manager

Salt formula-style dependency manager for masterless Salt repositories.

This repository is meant to be added to another Salt repository as a git
submodule. A bootstrap state can then apply `salt_dependency_manager` to clone
declared dependencies and write Salt config roots for future runs.

## Usage

Add this repository as a submodule and make sure the bootstrap state is
discoverable by `salt-local-bootstrap`:

```text
.salt-bootstrap-state
```

```text
salt_dependency_manager
```

Declare dependencies in pillar:

```yaml
salt_dependency_manager:
  dependencies:
    - url: https://github.com/saltstack-formulas/salt-formula.git
      sides:
        - minion
      pillar: true
      path: /root
      gitfs: false
      ref: master
```

The state clones non-gitfs dependencies to `<path>/<repo-name>`, adds each repo
root to `file_roots`, and adds `<repo-root>/pillar` to `pillar_roots` when
`pillar` is true. Minion-side config also sets `file_client: local` for
masterless operation.

For `gitfs: true`, the state does not clone the repository. It adds the
dependency to `gitfs_remotes` and, when `pillar` is true, adds it to
`ext_pillar` using the repository's `pillar` directory.

## Dependency Macro

Import the macro when you want to build a dependency entry from another Jinja
state or pillar file:

```jinja
{%- from "salt_dependency_manager/macros.jinja" import dependency with context %}
{%- load_yaml as docker_formula %}
{{ dependency(
  "https://github.com/saltstack-formulas/docker-formula.git",
  sides=["minion"],
  pillar=True,
  path="/root",
  gitfs=False,
  ref="master"
) }}
{%- endload %}
```

Arguments:

- `url`: dependency git URL.
- `sides`: `master`, `minion`, or a list containing either or both.
- `pillar`: whether to configure dependency pillar data. Defaults to `true`.
- `path`: parent directory for local clones. Defaults to `/root`.
- `gitfs`: use Salt gitfs/git_pillar instead of cloning. Defaults to `false`.
- `ref`: branch, tag, or commit. Defaults to `master`.
- `version`: alias for `ref` when that reads better in pillar.
- `name`: optional clone directory name. Defaults to the URL repo name.
- `env`: Salt environment for local roots and gitfs entries. Defaults to `base`.
- `pillar_root`: pillar subdirectory. Defaults to `pillar`.
- `update`: for local clones, update an existing checkout. Defaults to `true`.
- `options`: extra options passed to `git.latest`, `gitfs_remotes`, or
  `git_pillar`.

## Pillar Formats

The pillar-driven state accepts all of these forms:

```yaml
salt_dependency_manager:
  dependencies:
    - https://github.com/saltstack-formulas/salt-formula.git
    - https://github.com/saltstack-formulas/openssh-formula.git:
        sides: [minion]
        ref: master
    - url: https://github.com/saltstack-formulas/nginx-formula.git
      sides: [master, minion]
      gitfs: true
      pillar: true
      ref: master
```

The generated config files are:

- `/etc/salt/minion.d/salt-dependency-manager.conf`
- `/etc/salt/master.d/salt-dependency-manager.conf`

Salt reads these on later `salt-call --local` or daemon runs.

Note: Salt warns against placing sensitive pillar data under a path exposed by
`file_roots`. This manager follows the requested `<repo-root>/pillar` convention;
avoid storing secrets there unless the repository exposure model is acceptable.
