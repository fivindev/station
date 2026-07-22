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

echo "==> installing required ansible collections"
"$HOME/.local/bin/ansible-galaxy" collection install -r "$(dirname "$0")/requirements.yml"

cat <<'EOF'

Bootstrap complete.

If this is a new shell, make sure ~/.local/bin is on PATH (uv installs
ansible-playbook there). Then run, e.g.:

  ansible-playbook site.yml -e device_type=hermes-vps
EOF
