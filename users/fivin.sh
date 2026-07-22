#!/usr/bin/env bash
# Creates the fivin sudo user: SSH-key-only login, a real password for
# `sudo` only (prompted for interactively, never stored anywhere), sudo
# group membership, and SSH password authentication disabled
# specifically for this user via an sshd `Match User` block.
#
# Deliberately plain bash, not Ansible: fivin needs to exist BEFORE
# Ansible/uv are installed at all (bootstrap.sh and everything else in
# this repo is meant to be run AS fivin, not as root). Run once, as
# root, on a fresh Ubuntu/Debian device. Safe to re-run — updates the
# SSH key/sudo group/sshd config if the user already exists (and will
# re-prompt for a new password each time).
#
# Usage:
#   sudo ./fivin.sh "ssh-ed25519 AAAA... you@host"
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must be run as root (e.g. sudo $0 ...)" >&2
  exit 1
fi

ssh_key="${1:-}"
if [[ -z "$ssh_key" ]]; then
  echo "Usage: $0 \"ssh-ed25519 AAAA... you@host\"" >&2
  exit 1
fi
if [[ ! "$ssh_key" =~ ^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-) ]]; then
  echo "Doesn't look like an SSH public key: $ssh_key" >&2
  exit 1
fi

username=fivin

if id "$username" &>/dev/null; then
  echo "==> user $username already exists, updating its config"
else
  echo "==> creating user $username"
  useradd --create-home --shell /bin/bash "$username"
fi

usermod --append --groups sudo "$username"

echo "==> set a password for $username (used for sudo only — SSH login is key-only)"
passwd "$username"

home_dir="$(getent passwd "$username" | cut -d: -f6)"
install -d -m 0700 -o "$username" -g "$username" "$home_dir/.ssh"
echo "$ssh_key" >"$home_dir/.ssh/authorized_keys"
chmod 0600 "$home_dir/.ssh/authorized_keys"
chown "$username:$username" "$home_dir/.ssh/authorized_keys"

echo "==> disabling SSH password authentication for $username"
cat >/etc/ssh/sshd_config.d/fivin-no-password.conf <<EOF
Match User $username
    PasswordAuthentication no
EOF
systemctl reload ssh

cat <<EOF

Done. Reconnect as $username using your SSH key (SSH password login is
disabled for this user), then run ./bootstrap.sh as $username to set up
Ansible before running site.yml.
EOF
