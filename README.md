# salt-dependency-manager

Salt formula for materializing a complete, ordered repository graph and writing
the Salt roots for one environment. The formula is intended to be pinned as a
submodule of a root project and applied in a dedicated bootstrap Salt process.

## Contract

The only input is the compiled `salt_dependency_manager` Pillar mapping:

```yaml
salt_dependency_manager:
  schema: 1
  saltenv: example
  sides: [minion]
  install_path: /root
  repository_order: [project, salt_lib]
  repositories:
    project:
      source: local
      path: /root/project
      state_roots: ['.']
      pillar_roots: []
    salt_lib:
      source: git
      url: git@github.com:necr0manth/salt-lib.git
      ref: 547c56d52c756a941d64c22bf98d7d038fcc88ac
      state_roots: ['.']
      pillar_roots: []
```

`schema` must be `1`. `saltenv` names the generated root environment. `sides`
is a non-empty unique list containing `minion`, `master`, or both.
`repository_order` must list every repository ID exactly once and determines
root precedence.

A `local` repository requires an existing absolute `path` and is never cloned
or updated. A `git` repository requires `url`; its target is an explicit
absolute `path`, or `<install_path>/<URL basename>` when `path` is omitted.
Repositories default to `ref: HEAD`, `state_roots: ['.']`,
`pillar_roots: ['pillar']`, `update: true`, and `git_options: {}`. Root arrays
may be empty. Roots must be relative, must exist after materialization, and may
not escape the repository lexically or through symlinks.

`git_options` is passed to `git.latest`, except for manager-owned `name`,
`target`, `rev`, `update_head`, and `require`. Deployment policy may impose
additional restrictions on otherwise supported options such as `force_clone`,
`force_checkout`, or `force_reset`.

## Ownership and execution

For each selected side the formula owns exactly:

```text
/etc/salt/<side>.d/50-salt-dependency-manager-<saltenv>.conf
```

The file contains only the generated `file_roots` and `pillar_roots`. The
formula does not set `file_client`, add arbitrary roots, manage services, or
restart daemons. For each unselected side it removes only the exact manager
file above. It does not clean up any other configuration.

Bootstrap and normal state execution are separate processes because Salt does
not reload roots written during an already running state compilation:

```console
salt-call --local state.apply salt_dependency_manager \
  saltenv=example_dependencies pillarenv=example_dependencies
salt-call --local state.apply saltenv=example pillarenv=example
```

Applying the dependency state repeatedly is idempotent when repositories and
the generated configuration are already at their declared state.
