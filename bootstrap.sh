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
# passlib is required for the password_hash filter (used by roles/fivin)
uv tool install ansible --with passlib

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
