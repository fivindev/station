#!/usr/bin/env bash
# One-time setup: installs uv, then installs Ansible (via uv) and the
# collections this repo's roles depend on. Run once per fresh device,
# after cloning this repo, before any ansible-playbook command.
set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
  echo "==> installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "==> installing ansible via uv"
# Installing `ansible` (not ansible-core) as the top-level uv tool only
# exposes its own entry point (ansible-community, a version-printing
# script) — ansible-playbook/ansible-galaxy/etc. belong to ansible-core,
# which `ansible` merely depends on, so `uv tool install ansible` alone
# leaves them missing. Installing ansible-core as the tool exposes the
# real CLI; `--with ansible` still pulls in the full collection bundle,
# and passlib is required for the password_hash filter (used by
# roles/fivin).
uv tool uninstall ansible >/dev/null 2>&1 || true # clean up a stale install from before this fix
uv tool install ansible-core --with ansible --with passlib

# Makes sure ~/.local/bin is on PATH in your shell rc file going forward.
# Safe to run every time — it's a no-op if already wired up.
uv tool update-shell

echo "==> installing required ansible collections"
"$HOME/.local/bin/ansible-galaxy" collection install -r "$(dirname "$0")/requirements.yml"

cat <<'EOF'

Bootstrap complete.

IMPORTANT: this script cannot change the PATH of the shell you ran it
from — only new shells pick up ~/.local/bin. Before running
ansible-playbook, either open a new terminal / reconnect, or run:

  source ~/.bashrc

Then, e.g.:

  ansible-playbook site.yml -e device_type=hermes-vps
EOF
