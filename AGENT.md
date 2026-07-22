# Agent guidance for this repo

This is a personal Ansible provisioning repo (see README.md for the
full design). It currently manages one device type — `hermes-vps`, an
Ubuntu VPS — run locally via `ansible-playbook site.yml -e
device_type=hermes-vps`. The design supports multiple device types
sharing roles via `vars/profiles.yml` (a macOS laptop, a Raspberry Pi,
etc. were provisioned this way before and may come back later), so
don't hardcode assumptions that `hermes-vps` is the only device_type
that will ever exist — e.g. keep OS-specific branching keyed on
`ansible_facts`, not on `device_type == "hermes-vps"`.

## Conventions to follow when editing or adding roles

- **One role per thing.** Don't fold multiple unrelated tools into a
  single role — if you're adding both `docker` and `zsh`, that's two
  roles in `roles/`.
- **Every role needs both `tasks/main.yml` (install) and
  `tasks/uninstall.yml` (removal).** Uninstall is not optional — mirror
  each install step with an explicit removal step (package `state:
  absent`, symlink `state: absent`, removing a vendor install directory
  like `~/.nvm`/`~/.bun`, stripping shell-profile lines the installer
  added, etc.). Two narrow exceptions exist, and both say so explicitly
  rather than silently doing nothing: `roles/workspaces/tasks/uninstall.yml`
  is a deliberate no-op (the directory holds other roles' data by the
  time you'd remove it), and `roles/fivin/tasks/uninstall.yml` fails
  loudly with manual instructions (deleting a live user account
  unattended was judged too destructive to automate). If you add a role
  where uninstall genuinely can't or shouldn't be automated, follow one
  of those two patterns rather than leaving uninstall.yml empty or
  silently skipping it.
- **Root privileges are opt-in, not the default.** Neither `site.yml`
  nor `uninstall.yml` sets `become` at the play level. Any task that
  installs packages, writes outside `$HOME` (`/etc/...`), manages a
  systemd service, or manages user accounts/groups needs `become: true`
  set explicitly — either on the task itself, or on a wrapping `block:`
  when several tasks in a row all need it (see `roles/docker`,
  `roles/gh`, `roles/fivin`). Tasks that only touch files inside the
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
  change.
- **Tag propagation depends on `include_role` (dynamic), not
  `import_role` (static)**, and on the `tags: "{{ item }}"` pattern
  already used in `site.yml`/`uninstall.yml`. Don't "simplify" that to
  `import_role` — it will break `--tags <rolename>` filtering.

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
