# station

Personal provisioning repo. Ansible playbooks, run locally on whichever
device you're setting up, that install dotfiles, packages, toolchains, and
OS/desktop settings. Currently covers one device type — `hermes-vps`, an
Ubuntu VPS — but is built to have more device types (a macOS laptop, a
Raspberry Pi, etc.) added back in later without restructuring anything.

Everything runs against `localhost` (`connection: local`) — no inventory
file, no SSH, no remote control. You always run it *on* the device you're
provisioning.

**Almost nothing here is meant to be run as root.** There are two separate
playbooks:

- `fivin.yml` — a standalone, one-time bootstrap: creates a sudo user
  (`fivin`) with SSH-key-only login. Run once, as root (or whatever
  account you land on for a fresh device).
- `site.yml` — everything else (dotfiles, packages, toolchains). Meant to
  be run **as `fivin`**, after switching to that user — not as root. This
  is deliberately a separate playbook rather than a role in `site.yml`'s
  list, since different devices may end up wanting different admin-user
  setups, and user creation is a one-time bootstrap step, not part of a
  repeatable per-device role list.

## Fresh machine setup

**Stage 1 — as root, create the admin user:**

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

4. Create the `fivin` user:

   ```
   ansible-playbook fivin.yml -e fivin_ssh_public_key="ssh-ed25519 AAAA... you@host"
   ```

   `fivin_ssh_public_key` is required (the run fails loudly if it's
   missing — never store it in this repo). You'll be interactively
   prompted for a password for `fivin` (used for `sudo` only — SSH login
   for `fivin` is key-only; password auth over SSH is disabled
   specifically for this user via an sshd `Match User` block).

**Stage 2 — switch to `fivin`, provision everything else:**

5. Reconnect as `fivin` (`ssh fivin@this-host`, or `su - fivin` if
   you're still on the box).
6. Clone this repo again (into `fivin`'s own home — a separate copy from
   root's, since `fivin` needs its own working copy to actually run
   things), and run `./bootstrap.sh` again — `uv tool install` is
   per-user, so `fivin` needs their own Ansible install too.
7. Run the playbook, telling it what kind of device this is:

   ```
   ansible-playbook site.yml -e device_type=hermes-vps -K
   ```

   `device_type` must be one of the keys in `vars/profiles.yml`
   (currently just `hermes-vps`). `-K` (`--ask-become-pass`) is needed
   because `fivin` has no passwordless sudo — pass it whenever a task
   needs `become: true` (installing packages, mainly); Ansible prompts
   once and reuses it for every such task in the run.

## Day-to-day commands

Everything below (except `fivin.yml`/`fivin-uninstall.yml`) takes
`-e device_type=hermes-vps`, is meant to be run as `fivin`, and needs
`-K` whenever it touches a `become: true` task (installing/removing
packages).

| Goal | Command |
|---|---|
| Create the admin user (once, as root) | `ansible-playbook fivin.yml -e fivin_ssh_public_key="..."` |
| Install everything for this device | `ansible-playbook site.yml -e device_type=hermes-vps -K` |
| Install just one role | `ansible-playbook site.yml -e device_type=hermes-vps --tags docker -K` |
| Uninstall everything for this device | `ansible-playbook uninstall.yml -e device_type=hermes-vps -K` |
| Uninstall just one role | `ansible-playbook uninstall.yml -e device_type=hermes-vps --tags docker -K` |
| Reinstall a role (uninstall + install) | `ansible-playbook uninstall.yml -e device_type=hermes-vps --tags docker -K && ansible-playbook site.yml -e device_type=hermes-vps --tags docker -K` |
| Dry-run (show what would change) | `ansible-playbook site.yml -e device_type=hermes-vps --check --diff` |
| List available roles | `ansible-playbook site.yml --list-tags` |
| Attempt to remove the admin user (fails loudly on purpose) | `ansible-playbook fivin-uninstall.yml` |

## Repo structure

```
fivin.yml               # standalone: creates the fivin admin user (run once, as root)
fivin-uninstall.yml     # companion — fails loudly with manual removal steps
site.yml                # install playbook — applies common + profiles[device_type] roles
uninstall.yml           # same role selection, runs each role's uninstall.yml instead
vars/profiles.yml       # device_type -> role list (edit this to add a role to a device)
roles/<name>/
  tasks/main.yml        # install steps
  tasks/uninstall.yml   # removal steps (mirrors main.yml)
  meta/main.yml         # role dependencies, if any (Ansible resolves these automatically)
  files/, templates/    # dotfiles symlinked/rendered into $HOME
bootstrap.sh            # one-time per user: installs uv, ansible, and collections
requirements.yml        # ansible-galaxy collections this repo depends on (currently none)
```

Current roles (all under `site.yml`/`vars/profiles.yml`, run as `fivin`):

- `git` — under `common`, applies to every device type. Installs git,
  symlinks `~/.gitconfig`.
- `gh` — under `common`. Installs the GitHub CLI via its own recommended
  method per OS: apt repository on Debian/Ubuntu, Homebrew on macOS.
- `workspaces` — under `common`. Ensures `~/workspaces` exists.
- `docker`, `nvm`, `bun` — under `hermes-vps`. Each installed via that
  tool's own recommended method (apt repository for Docker,
  version-pinned `curl | bash` installers for nvm/bun), not a generic
  package manager entry. `nvm` also installs the latest Node LTS.
  `docker` adds whoever is running the playbook (`fivin`, once `fivin`
  runs it) to the `docker` group.
- `hermes` — under `hermes-vps`. Deploys `~/workspaces/hermes/docker-compose.yaml`
  plus a generated `.env`. The basic-auth secret is randomly generated on
  first run and persisted to `~/workspaces/hermes/.basic_auth_secret` (so
  re-running the playbook doesn't rotate it); the compose file references
  it as `${HERMES_DASHBOARD_BASIC_AUTH_SECRET}` rather than a literal
  value. Does **not** run `docker compose up -d` — that's a manual step.
  The dashboard username/password (`admin`/`password`) are left as
  literal placeholders from the source file; change them yourself if
  you're actually exposing the dashboard.

`fivin` (used only by `fivin.yml`/`fivin-uninstall.yml`, not part of any
`vars/profiles.yml` list): creates the sudo user described above.
**Has no real uninstall** — `fivin-uninstall.yml` fails loudly with
manual removal instructions instead, since deleting a live user account
isn't something this repo automates.

## Adding something new

1. `ansible-galaxy init roles/<name>` (or copy an existing role as a starting point).
2. Write `tasks/main.yml` (install) and `tasks/uninstall.yml` (removal).
   Use `ansible.builtin.package` for packages so it works across apt and
   Homebrew, unless the tool's own docs recommend a different specific
   method (see `docker`/`nvm`/`bun` above) — follow that instead. Use
   `ansible.builtin.file` with `state: link` to symlink dotfiles from
   the role's `files/` dir into `$HOME` (referenced as `{{ home_dir }}`
   — see below); if something already exists at the target path, back
   it up first rather than overwriting.
3. Add `<name>` to the relevant list(s) in `vars/profiles.yml` — put it
   under `common` if every device type should get it, or under a specific
   device type if not.
4. If it needs another role to run first, declare that in
   `roles/<name>/meta/main.yml` under `dependencies:`.
5. Nothing runs as root by default. Tasks that install packages, write
   outside `$HOME`, manage services, or manage user accounts need
   `become: true` explicitly (on the task, or on a wrapping `block:` if
   several tasks in a row need it — see `roles/docker`, `roles/gh`).
   Tasks that just touch files in the invoking user's own `$HOME`
   (dotfiles, `~/workspaces/...`) should *not* set `become`, or the
   files it creates end up root-owned instead of user-owned.
6. Reference the invoking user's home directory as `{{ home_dir }}` (a
   var defined once in `site.yml`/`uninstall.yml`, resolving to
   `ansible_facts['env']['HOME']`) — not `ansible_env.HOME` directly,
   which is a deprecated shortcut Ansible plans to remove.
7. Adding a new device type: add a key + role list to `vars/profiles.yml`,
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
