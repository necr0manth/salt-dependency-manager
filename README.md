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

Either declare dependencies in a state with the reusable macro:

```jinja
{%- from "salt_dependency_manager/macros.jinja" import dependency, manage_dependencies with context %}

{%- set salt_lib = dependency(
  "git@github.com:necr0manth/salt-lib.git",
  sides=["minion"],
  pillar=False,
  path="/root",
  ref="main"
)|load_yaml %}

{{ manage_dependencies(
  [salt_lib],
  config_name="main",
  file_roots=["/root/salt-main"],
  pillar_roots=["/root/salt-main/pillar"]
) }}
```

or declare dependencies in pillar and apply `salt_dependency_manager` directly:

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

## Dependency Macros

Import the macros when you want to build dependency entries from another Jinja
state or pillar file:

```jinja
{%- from "salt_dependency_manager/macros.jinja" import dependency, manage_dependencies with context %}
{%- set docker_formula = dependency(
  "https://github.com/saltstack-formulas/docker-formula.git",
  sides=["minion"],
  pillar=True,
  path="/root",
  gitfs=False,
  ref="master"
)|load_yaml %}
{{ manage_dependencies([docker_formula], config_name="my_repo") }}
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

`manage_dependencies(dependencies, config_name=None, config_basename=None,
file_roots=None, pillar_roots=None, target_sides=None)` emits the Salt states
that install git, clone applicable non-gitfs dependencies, and write Salt
config for the requested sides. Set `config_name` from the declaring repository
or state, such as `main`; it namespaces generated Salt IDs and writes a config
file such as `/etc/salt/minion.d/salt-dependency-manager-main.conf`.

Optional `config_basename`, `file_roots`, and `pillar_roots` arguments let the
declaring repository own a single combined config file. For example,
`config_basename="salt-vps1"`, `file_roots=["/root/salt-vps1"]`, and
`pillar_roots=["/root/salt-vps1/pillar"]` writes
`/etc/salt/minion.d/salt-vps1.conf` with those local roots first, followed by
managed dependency roots.

### Dependency applicability and invocation targets

`dependency(..., sides=...)` declares where that dependency is applicable.
`manage_dependencies(..., target_sides=...)` independently selects which Salt
component configs this particular invocation writes on the current machine.
It does not select remote machines or perform remote installation.

The three target forms are:

```jinja
{{ manage_dependencies(dependencies, target_sides=["minion"]) }}
{{ manage_dependencies(dependencies, target_sides=["master"]) }}
{{ manage_dependencies(dependencies, target_sides=["minion", "master"]) }}
```

The first writes only the minion config, the second writes only the master
config, and the third configures both components on the same machine. A string
or iterable is accepted; duplicates are ignored in first-seen order. Omitting
`target_sides` preserves the default behavior: the invocation uses the stable
union of all declared dependency sides. An explicitly requested side is still
written when no dependency applies to it, so caller-provided `file_roots` and
`pillar_roots` can configure that component by themselves.

Only dependencies whose `sides` intersect `target_sides` are active for that
invocation. Local dependencies are cloned once even when they apply to both
sides, and git is installed only when an active local dependency needs it.
Each generated config contains only dependencies applicable to that side.
Minion config sets `file_client: local`; master config does not.

These states execute locally wherever the Salt command itself runs. A
masterless minion example is:

```console
salt-call --local state.apply example.dependencies.masterless
```

A Salt master orchestration example is:

```console
salt-run state.orchestrate example.dependencies.master
```

In both cases, `target_sides` controls local config generation, not command
targeting. Future Salt processes read the newly configured roots. An already
running Salt master may need to be restarted before it sees master-side config
changes; this formula does not restart daemons.

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

Depending on the requested or declared sides, generated config paths are:

- `/etc/salt/minion.d/salt-dependency-manager.conf`
- `/etc/salt/master.d/salt-dependency-manager.conf`

Salt reads these on later `salt-call --local` or daemon runs. Applying only one
`target_sides` value neither writes nor removes the other side's config.

Note: Salt warns against placing sensitive pillar data under a path exposed by
`file_roots`. This manager follows the requested `<repo-root>/pillar` convention;
avoid storing secrets there unless the repository exposure model is acceptable.

## Transitive Dependencies

Prefer declaring dependencies in a repository-owned state, for example
`main.dependencies` or `salt-lib.dependencies`, using `dependency()` and
`manage_dependencies()`. This avoids a shared pillar key where one repository's
dependency list can overwrite another's.

Salt renders an SLS before states in that SLS clone new repositories, so a
freshly cloned dependency's own `*.dependencies` state cannot be discovered and
compiled in the same render pass automatically. The reliable pattern is:

- the root repository's bootstrap state applies its own `<repo>.dependencies`;
- each dependency that has dependencies declares them in its own
  `<repo>.dependencies` state;
- apply the dependency state again after the new repository root is available,
  or include those dependency states explicitly once they are part of the
  configured roots.
