# Agent guidance for this repo

This is a personal Ansible provisioning repo (see README.md for the
full design). It currently manages one device type — `hermes-vps`, an
Ubuntu VPS. Provisioning it is two stages:

1. `users/fivin.sh` — plain bash, NOT Ansible — run once as root,
   creates a sudo user (`fivin`) with SSH-key-only login. It has to be
   plain bash rather than a playbook: `fivin` must exist *before*
   Ansible/uv are installed at all, since `bootstrap.sh`/`site.yml` are
   themselves meant to run as `fivin`, not root. Standalone for a
   second reason too — different devices may want different admin-user
   setups, and user creation is a one-time bootstrap step, not part of
   the repeatable per-device role list. Don't try to fold this back
   into an Ansible role/playbook.
2. `site.yml -e device_type=hermes-vps`, run as `fivin` (not root) after
   switching users, does everything else (dotfiles, packages,
   toolchains).

Because `site.yml` is invoked BY `fivin` themselves (not by root using
`become_user` tricks), `ansible_facts['env']['HOME']` / `ansible_facts['user_id']`
naturally resolve to `fivin`'s own context with no special-casing
anywhere in the git/gh/workspaces/docker/nvm/bun/hermes roles. Don't
reintroduce `become_user`-switching logic to simulate "run as a specific
user" — the two-stage split already gets you that, more simply.

The design supports multiple device types sharing roles via
`vars/profiles.yml` (a macOS laptop, a Raspberry Pi, etc. were
provisioned this way before and may come back later), so don't hardcode
assumptions that `hermes-vps` is the only device_type that will ever
exist — e.g. keep OS-specific branching keyed on `ansible_facts`, not on
`device_type == "hermes-vps"`.

## Conventions to follow when editing or adding roles

- **One role per thing.** Don't fold multiple unrelated tools into a
  single role — if you're adding both `docker` and `zsh`, that's two
  roles in `roles/`.
- **Every role needs both `tasks/main.yml` (install) and
  `tasks/uninstall.yml` (removal).** Uninstall is not optional — mirror
  each install step with an explicit removal step (package `state:
  absent`, symlink `state: absent`, removing a vendor install directory
  like `~/.nvm`/`~/.bun`, stripping shell-profile lines the installer
  added, etc.). `roles/workspaces/tasks/uninstall.yml` is a deliberate
  exception — a no-op that says so explicitly (the directory holds
  other roles' data by the time you'd remove it) rather than silently
  doing nothing. If you add a role where uninstall genuinely can't or
  shouldn't be automated, follow that pattern (an explicit, explained
  no-op) rather than leaving uninstall.yml empty or silently skipping
  it. `users/fivin.sh` (outside the role system entirely) has no
  uninstall counterpart at all — deleting a live user account was
  judged too risky to script even as a "fails loudly" stub; README.md
  documents the manual removal steps instead. Don't add one back
  without being asked.
- **Root privileges are opt-in, not the default.** Neither `site.yml`
  nor `uninstall.yml` sets `become` at the play level. Any task that
  installs packages, writes outside `$HOME` (`/etc/...`), manages a
  systemd service, or manages user accounts/groups needs `become: true`
  set explicitly — either on the task itself, or on a wrapping `block:`
  when several tasks in a row all need it (see `roles/docker`,
  `roles/gh`). Tasks that only touch files inside the
  invoking user's own `$HOME` (dotfiles, `~/workspaces/...`) must NOT
  set `become` — under `become: true` they'd create root-owned files in
  the user's home directory instead of user-owned ones. When adding a
  role, check every task that touches the filesystem or a package
  manager and decide explicitly which side of that line it's on; don't
  assume the previous task's `become` setting carries over silently.
- **Use `ansible.builtin.package`**, not `apt`/`community.general.homebrew`
  directly, for anything installable on both Debian-family (apt) and
  macOS (Homebrew) — unless the package name genuinely differs between
  the two, in which case branch on `ansible_facts['os_family']` /
  `ansible_facts['system'] == "Darwin"` just for that one task.
  Exception: if a tool's own docs recommend a specific install method
  that isn't a plain package-manager entry (e.g. Docker's apt-repo
  setup, or a vendor's `curl | bash` installer like nvm/bun), follow
  that method instead — don't force it through `package` just for
  consistency. Guard vendor install scripts with `creates:` so re-runs
  are no-ops (see `roles/nvm`, `roles/bun`, `roles/docker`).
- **Dotfiles are symlinked, not copied**, from the role's `files/` dir
  into `$HOME` via `ansible.builtin.file` with `state: link`. Before
  linking, check with `ansible.builtin.stat` whether a real file
  already exists at the target and back it up (`mv` to a
  `.bak.<timestamp>` name) rather than overwriting it — never silently
  discard something that might be a local customization.
- **Role dependencies go in `roles/<name>/meta/main.yml`** under
  `dependencies:`, not as ad-hoc `include_role` calls inside
  `tasks/main.yml`. Ansible resolves and orders these automatically.
- **New roles are registered in `vars/profiles.yml`**, not by editing
  `site.yml`/`uninstall.yml`. Those two playbooks read the role list
  for a device_type dynamically; they should almost never need to
  change. Admin-user creation (`users/fivin.sh`) is a deliberate
  exception, and lives entirely outside the role system — it's not an
  Ansible role at all (see the top of this file for why). If another
  device needs its own admin-user setup later, its script(s) belong in
  `users/` too (e.g. `users/<name>.sh`) — that directory is reserved for
  this category of standalone, one-time, pre-Ansible bootstrap script,
  distinct from `site.yml`/`uninstall.yml` and `roles/` at the repo root.
- **Reference the invoking user's home as `{{ home_dir }}`**, a var
  defined once in `site.yml`/`uninstall.yml` (`ansible_facts['env']['HOME']`),
  not the deprecated bare `ansible_env.HOME` shortcut. Same goes for any
  other fact: use `ansible_facts['x']`, never the bare `ansible_x` form
  — `INJECT_FACTS_AS_VARS` (what makes the bare form work at all) is
  deprecated and slated for removal in ansible-core 2.24.
- **Tag propagation depends on `include_role` (dynamic), not
  `import_role` (static — it also doesn't support `loop` at all).**
  Don't "simplify" that to `import_role`.
  Putting `tags: "{{ item }}"` directly on the `include_role` task
  looks like it should work but doesn't — Ansible resolves a task's own
  `tags:` during a static pre-pass before the loop variable is bound,
  so it fails with `'item' is undefined`. The actual working pattern
  (used in `site.yml`/`uninstall.yml`) is `apply: tags: "{{ item }}"`
  nested inside `include_role`, with a plain `tags: always` on the
  include task itself so it's never filtered out; `apply.tags` is
  evaluated per-iteration and propagates onto the tasks the role brings
  in. Don't move the loop-var tag back onto the bare `tags:` key.

## What NOT to add

- No secrets, SSH keys, tokens, or credentials in this repo (not even
  encrypted/vaulted) — that was an explicit scope decision, not an
  oversight.
- No inventory file / remote hosts — this repo only ever targets
  `localhost` with `connection: local`. Don't add SSH-based host
  management.
- No CLI wrapper script (`run.sh`, Makefile, etc.) — `ansible-playbook`
  is called directly. Don't reintroduce a wrapper "for convenience"
  without being asked.

## Before considering a change done

- For any role touching packages or dotfiles, mentally (or actually,
  via `--check --diff`) walk through both the install and uninstall
  path — a role that installs cleanly but leaves files behind on
  uninstall is an incomplete change here.
- Prefer `ansible-playbook site.yml -e device_type=<x> --check --diff`
  over assuming a task is correct; this repo has no test suite, so a
  dry run is the review step.
