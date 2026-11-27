#!/usr/bin/env bash
# Exercise OpenSSH signing with its packaged software FIDO test provider.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
unset GIT_CONFIG_GLOBAL SSH_AUTH_SOCK
export SSH_SK_PROVIDER=${YUBIKEY_TEST_PROVIDER:-/usr/lib/openssh/regress/misc/sk-dummy/sk-dummy.so}
export SSH_SK_HELPER=/usr/lib/openssh/ssh-sk-helper
[[ -r "$SSH_SK_PROVIDER" ]] || { echo "Install the openssh-tests package" >&2; exit 1; }
mkdir -p "$HOME/.ssh" "$tmp/bin"
cd "$HOME"
git config --global user.email tester@example.org
git config --global user.name Tester
state=$HOME/.ssh/yubikey
yk() { bash "$root/scripts/yubikey-ssh" "$@"; }
reject() { if "$@"; then echo "Unexpected success: $*" >&2; exit 1; fi; }

cat > "$HOME/ssh-config" <<'EOF'
User default-user
Host test-box
    HostName example.org
    Port 2222
EOF
ln -s ../ssh-config "$HOME/.ssh/config"
printf '\ncreate\n' | yk setup
[[ $(readlink "$state/active") == nano ]]
[[ $(stat -c %a "$state/nano/identity") == 600 ]]
reject yk use nfc
reject yk host 'bad host'
[[ $(readlink "$state/active") == nano ]]
git init -q repo
git -C repo commit -qm nano --allow-empty
git -C repo verify-commit HEAD

yk setup nfc create
git -C repo commit -qm nfc --allow-empty
git -C repo verify-commit HEAD
git -C repo verify-commit HEAD^
[[ $(git -C repo log -1 --format=%GF) == "$(ssh-keygen -lf "$state/nfc/identity.pub" | awk '{print $2}')" ]]
[[ $(git -C repo log -1 --format=%GF HEAD^) == "$(ssh-keygen -lf "$state/nano/identity.pub" | awk '{print $2}')" ]]
yk use nano
printf 'n\nn\ngpg\n\n' | GNUPGHOME="$tmp/gpg" bash "$root/setup-secrets.sh"
[[ $(git config gpg.format) == openpgp ]]
git -C repo verify-commit HEAD
[[ $(git config user.signingkey) == "$(git config -f "$root/config/git/gitconfig" user.signingkey)" ]]
printf 'n\nn\nkeep\n' | bash "$root/setup-secrets.sh"
[[ $(git config gpg.format) == openpgp ]]
yk use nfc
[[ $(git config gpg.format) == ssh ]]
printf 'n\nn\nyubikey\nnano\n' | bash "$root/setup-secrets.sh"
[[ $(readlink "$state/active") == nano ]]
yk setup nano create
[[ $(wc -l < "$state/allowed_signers") == 2 ]]
[[ $(git config --global --get-all include.path | wc -l) == 1 ]]
yk host test-box
yk host test-box
[[ -L "$HOME/.ssh/config" && $(grep -c '^Include ' "$HOME/ssh-config") == 1 ]]
[[ $(grep -c '^Host test-box$' "$state/hosts.conf") == 1 ]]
# OpenSSH expands ~ via passwd. Point the Include at the isolated test home.
sed "1s|~|$HOME|" "$HOME/.ssh/config" > "$tmp/client.conf"
settings=$(ssh -G -F "$tmp/client.conf" test-box)
for value in 'hostname example.org' 'user default-user' 'port 2222' 'identitiesonly yes' 'identityfile ~/.ssh/yubikey/active/identity'; do
  grep -Fxq "$value" <<< "$settings"
done
other=$(ssh -G -F "$tmp/client.conf" other)
! grep -Fq 'yubikey/active/identity' <<< "$other" || exit 1
yk doctor

# Pre-start a test agent with a bounded lifetime (ssh-agent exits with its child).
ssh-agent -P "$SSH_SK_PROVIDER" -a "$state/nano/agent.sock" bash -eu -c '
  root=$1 state=$2 tmp=$3
  unset SSH_AUTH_SOCK
  yk() { bash "$root/scripts/yubikey-ssh" "$@"; }
  reject() { if "$@"; then exit 1; fi; }
  reject yk forward "*"
  yk forward test-box
  yk forward test-box
  [[ $(grep -c "^Host test-box$" "$state/forward.conf") == 1 ]]
  sed "1s|~|$HOME|g" "$HOME/.ssh/config" > "$tmp/client.conf"
  ssh -G -F "$tmp/client.conf" test-box > "$tmp/on"
  grep -Fq "active/agent.sock" "$tmp/on"
  ssh -G -F "$tmp/client.conf" other > "$tmp/off"
  grep -Fxq "forwardagent no" "$tmp/off"
  export SSH_AUTH_SOCK="$state/active/agent.sock"
  expected=$(cut -d" " -f1,2 "$state/active/identity.pub")
  [[ $(ssh-add -L | cut -d" " -f1,2) == "$expected" ]]
  git init -q "$tmp/remote"
  git -C "$tmp/remote" config user.email remote@example.org
  git -C "$tmp/remote" config user.name Remote
  export repo="$tmp/remote" expected
  sh "$root/lib/yubikey-remote-signing.sh"
  sh "$root/lib/yubikey-remote-signing.sh"
  [[ $(git -C "$repo" config --local --get-all include.path | wc -l) == 1 ]]
  git -C "$repo" commit -qm forwarded --allow-empty
  git -C "$repo" verify-commit HEAD
  bash "$root/sandbox/verify-forwarded-signing.sh" "$root" "$state" "$tmp" "$repo"
  yk forward --off test-box
  ssh -G -F "$tmp/client.conf" test-box > "$tmp/off"
  grep -Fxq "forwardagent no" "$tmp/off"
  [[ $(yk forward --list | awk "/^test-box/ {print \$2}") == off ]]
' _ "$root" "$state" "$tmp"

# Run the remote sh payload in a second home to check retry and key restrictions.
export REMOTE_HOME="$tmp/server-home"
mkdir -p "$REMOTE_HOME/.ssh"
printf 'restrict ' > "$REMOTE_HOME/.ssh/authorized_keys"
cat "$state/nfc/identity.pub" >> "$REMOTE_HOME/.ssh/authorized_keys"
cat > "$tmp/bin/ssh" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -T && $2 == tester@test-box ]] || exit 1
shift 2
HOME="$REMOTE_HOME" exec "$@"
EOF
chmod +x "$tmp/bin/ssh"
PATH="$tmp/bin:$PATH" yk host --install tester@test-box
PATH="$tmp/bin:$PATH" yk host --install tester@test-box
[[ $(grep -c 'sk-ssh-ed25519' "$REMOTE_HOME/.ssh/authorized_keys") == 2 ]]
grep -q '^restrict sk-ssh-ed25519' "$REMOTE_HOME/.ssh/authorized_keys"

# Simulate only resident-key enumeration. Signatures, handles and Git are real.
export RECOVERY="$tmp/recovery"
mkdir "$RECOVERY"
cp "$state/nfc/identity" "$RECOVERY/id_ed25519_sk_rk_nfc_abcd"
cp "$state/nfc/identity.pub" "$RECOVERY/id_ed25519_sk_rk_nfc_abcd.pub"
cat > "$tmp/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -K ]]; then cp -- "$RECOVERY/"* .; exit; fi
exec /usr/bin/ssh-keygen "$@"
EOF
chmod +x "$tmp/bin/ssh-keygen"
export PATH="$tmp/bin:$PATH"
export HOME="$tmp/new-home" XDG_CONFIG_HOME="$tmp/new-home/.config"
mkdir -p "$HOME/.ssh"
git config --global user.email tester@example.org
cp "$state/nano/identity" "$HOME/.ssh/id_ed25519_sk_nano"
cp "$state/nano/identity.pub" "$HOME/.ssh/id_ed25519_sk_nano.pub"
yk setup nano
cmp "$HOME/.ssh/yubikey/active/identity" "$state/nano/identity"
cp "$RECOVERY/id_ed25519_sk_rk_nfc_abcd" "$RECOVERY/id_ed25519_sk_rk_nfc_other"
cp "$RECOVERY/id_ed25519_sk_rk_nfc_abcd.pub" "$RECOVERY/id_ed25519_sk_rk_nfc_other.pub"
reject yk setup nfc import
[[ $(readlink "$HOME/.ssh/yubikey/active") == nano ]]
rm "$RECOVERY/id_ed25519_sk_rk_nfc_other" "$RECOVERY/id_ed25519_sk_rk_nfc_other.pub"
yk setup nfc import
cmp "$HOME/.ssh/yubikey/active/identity" "$state/nfc/identity"
echo "OK   YubiKey enrollment, key selection, SSH config, Git signing and recovery"
