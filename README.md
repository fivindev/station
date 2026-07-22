# station

Personal provisioning repo. One Ansible playbook, run locally on whichever
device you're setting up, that installs dotfiles, packages, toolchains, and
OS/desktop settings. Currently covers one device type — `hermes-vps`, an
Ubuntu VPS — but is built to have more device types (a macOS laptop, a
Raspberry Pi, etc.) added back in later without restructuring anything.

Everything runs against `localhost` (`connection: local`) — no inventory
file, no SSH, no remote control. You always run it *on* the device you're
provisioning.

## Fresh machine setup

1. Install git manually (`apt install git` / already present on macOS).
2. Clone this repo.
3. Run the bootstrap script once (installs [uv](https://docs.astral.sh/uv/),
   then Ansible via uv, then this repo's required Ansible collections):

   ```
   ./bootstrap.sh
   ```

   The script can't change the PATH of the shell you ran it from —
   only new shells pick up `~/.local/bin` (where uv installs
   `ansible-playbook`). Open a new terminal/SSH session, or run
   `source ~/.bashrc`, before the next step. If you skip this you'll
   see `ansible-playbook: command not found`.

4. Run the playbook, telling it what kind of device this is:

   ```
   ansible-playbook site.yml -e device_type=hermes-vps \
     -e fivin_ssh_public_key="ssh-ed25519 AAAA... you@host"
   ```

   `device_type` must be one of the keys in `vars/profiles.yml`
   (currently just `hermes-vps`). On `hermes-vps`, `fivin_ssh_public_key`
   is required (the run fails loudly if it's missing), and you'll be
   interactively prompted for a password for the `fivin` sudo user
   (used for `sudo` only — SSH login for `fivin` is key-only).

## Day-to-day commands

Everything below takes `-e device_type=hermes-vps`.

| Goal | Command |
|---|---|
| Install everything for this device | `ansible-playbook site.yml -e device_type=hermes-vps` |
| Install just one role | `ansible-playbook site.yml -e device_type=hermes-vps --tags docker` |
| Uninstall everything for this device | `ansible-playbook uninstall.yml -e device_type=hermes-vps` (stops at `fivin` — see below) |
| Uninstall just one role | `ansible-playbook uninstall.yml -e device_type=hermes-vps --tags docker` |
| Reinstall a role (uninstall + install) | `ansible-playbook uninstall.yml -e device_type=hermes-vps --tags docker && ansible-playbook site.yml -e device_type=hermes-vps --tags docker` |
| Dry-run (show what would change) | `ansible-playbook site.yml -e device_type=hermes-vps --check --diff` |
| List available roles | `ansible-playbook site.yml --list-tags` |

## Repo structure

```
site.yml              # install playbook — applies common + profiles[device_type] roles
uninstall.yml          # same role selection, runs each role's uninstall.yml instead
vars/profiles.yml      # device_type -> role list (edit this to add a role to a device)
roles/<name>/
  tasks/main.yml       # install steps
  tasks/uninstall.yml  # removal steps (mirrors main.yml)
  meta/main.yml         # role dependencies, if any (Ansible resolves these automatically)
  files/, templates/    # dotfiles symlinked/rendered into $HOME
bootstrap.sh           # one-time: installs uv, ansible, and collections
requirements.yml       # ansible-galaxy collections this repo depends on (currently none)
```

Current roles:

- `git` — under `common`, applies to every device type. Installs git,
  symlinks `~/.gitconfig`.
- `gh` — under `common`. Installs the GitHub CLI via its own recommended
  method per OS: apt repository on Debian/Ubuntu, Homebrew on macOS.
- `workspaces` — under `common`. Ensures `~/workspaces` exists.
- `docker`, `nvm`, `bun` — under `hermes-vps`. Each installed via that
  tool's own recommended method (apt repository for Docker,
  version-pinned `curl | bash` installers for nvm/bun), not a generic
  package manager entry. `nvm` also installs the latest Node LTS.
- `hermes` — under `hermes-vps`. Deploys `~/workspaces/hermes/docker-compose.yaml`
  plus a generated `.env`. The basic-auth secret is randomly generated on
  first run and persisted to `~/workspaces/hermes/.basic_auth_secret` (so
  re-running the playbook doesn't rotate it); the compose file references
  it as `${HERMES_DASHBOARD_BASIC_AUTH_SECRET}` rather than a literal
  value. Does **not** run `docker compose up -d` — that's a manual step.
  The dashboard username/password (`admin`/`password`) are left as
  literal placeholders from the source file; change them yourself if
  you're actually exposing the dashboard.
- `fivin` — under `hermes-vps`. Creates a sudo user `fivin`: SSH login is
  key-only (the public key is a required `-e fivin_ssh_public_key=...`
  at runtime — never stored in this repo), password login over SSH is
  disabled specifically for this user via an sshd `Match User` block, but
  a real password is set (prompted for interactively on each run) so
  `sudo` still works normally. Joins the `docker` group only if it
  already exists (order matters: `fivin` runs after `docker` in
  `vars/profiles.yml`). **Has no real `uninstall.yml`** — it fails
  loudly with manual removal instructions instead, since deleting a
  live user account isn't something this repo automates. That means
  "uninstall everything" on `hermes-vps` will stop when it reaches
  `fivin`; add `--skip-tags fivin` to uninstall everything else.

## Adding something new

1. `ansible-galaxy init roles/<name>` (or copy an existing role as a starting point).
2. Write `tasks/main.yml` (install) and `tasks/uninstall.yml` (removal).
   Use `ansible.builtin.package` for packages so it works across apt and
   Homebrew, unless the tool's own docs recommend a different specific
   method (see `docker`/`nvm`/`bun` above) — follow that instead. Use
   `ansible.builtin.file` with `state: link` to symlink dotfiles from
   the role's `files/` dir into `$HOME`; if something already exists at
   the target path, back it up first rather than overwriting.
3. Add `<name>` to the relevant list(s) in `vars/profiles.yml` — put it
   under `common` if every device type should get it, or under a specific
   device type if not.
4. If it needs another role to run first, declare that in
   `roles/<name>/meta/main.yml` under `dependencies:`.
5. Nothing runs as root by default. Tasks that install packages, write
   outside `$HOME`, manage services, or manage user accounts need
   `become: true` explicitly (on the task, or on a wrapping `block:` if
   several tasks in a row need it — see `roles/docker`, `roles/gh`,
   `roles/fivin`). Tasks that just touch files in the invoking user's
   own `$HOME` (dotfiles, `~/workspaces/...`) should *not* set `become`,
   or the files it creates end up root-owned instead of user-owned.
6. Adding a new device type: add a key + role list to `vars/profiles.yml`,
   then run with `-e device_type=<key>`.

No changes to `site.yml`/`uninstall.yml` are needed to add a role or a
device type — they read the role list from `vars/profiles.yml` dynamically.

## Out of scope by design

- **Secrets**: this repo doesn't manage SSH keys, tokens, or credentials.
  Handle those separately (password manager, manual copy).
- **Remote/fleet control**: no inventory of remote hosts, no SSH-based
  management of other machines from one control node. Always run locally.
- **A CLI wrapper**: no `run.sh`/Makefile shortcuts — use `ansible-playbook`
  directly as shown above.
