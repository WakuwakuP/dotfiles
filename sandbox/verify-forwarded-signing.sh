#!/usr/bin/env bash
# Called with the isolated homes, test credentials and agent from verify-yubikey-ssh.
set -euo pipefail
root=$1 state=$2 tmp=$3 legacy_repo=$4
export account_home="$tmp/remote-account"
mkdir -p "$account_home" "$tmp/transport"
# Exercise the --on install payload without touching the caller's Git settings.
cat > "$tmp/transport/ssh" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-T -o ControlPath=none test-box sh -s" ]
export HOME="$account_home" XDG_CONFIG_HOME="$account_home/.config"
cd "$HOME"
exec sh -s
EOF
chmod +x "$tmp/transport/ssh"
for attempt in 1 2; do
  PATH="$tmp/transport:$PATH" bash "$root/scripts/yubikey-ssh" forward --on test-box
done
mkdir "$tmp/linked-home"
cp "$root/config/git/gitconfig" "$tmp/linked-config"
ln -s "$tmp/linked-config" "$tmp/linked-home/.gitconfig"
account_home="$tmp/linked-home" PATH="$tmp/transport:$PATH" bash "$root/scripts/yubikey-ssh" forward --on test-box
cmp "$root/config/git/gitconfig" "$tmp/linked-config"
[[ -L "$tmp/linked-home/.gitconfig" ]]
[[ $(bash "$root/scripts/yubikey-ssh" forward --list | awk '$1=="test-box" {print $2}') == on ]]
export HOME="$account_home" XDG_CONFIG_HOME="$account_home/.config"
cd "$HOME"
[[ $(git config --global --get-all include.path | wc -l) == 1 ]]
git config --global user.name Forwarded
git config --global user.email tester@example.org
git config --global gpg.ssh.allowedSignersFile "$state/allowed_signers"
git init -q fresh
# Change the identity offered by the session, without configuring either repo again.
for role in nano nfc; do
  if [[ $role == nfc ]]; then
    ssh-add -d "$state/nano/identity.pub"
    ssh-add "$state/nfc/identity"
    git config --global user.signingkey old-openpgp-fingerprint
  fi
  fingerprint=$(ssh-keygen -lf "$state/$role/identity.pub" | awk '{print $2}')
  for repo in fresh "$legacy_repo"; do
    git -C "$repo" commit --allow-empty -qm "$role"
    git -C "$repo" verify-commit HEAD
    [[ $(git -C "$repo" log -1 --format=%GF) == "$fingerprint" ]]
  done
done
if SSH_AUTH_SOCK="$tmp/absent" git -C fresh commit --allow-empty -qm absent; then exit 1; fi
ssh-add "$state/nano/identity"
if git -C fresh commit --allow-empty -qm ambiguous; then exit 1; fi
printf 'OK   Account signing follows a single forwarded key across repositories\n'
