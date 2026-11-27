# Runs via sh -s on the development host, with repo and expected set by the client.
set -eu
case $repo in
  '~') repo=$HOME ;;
  '~/'*) repo=$HOME/${repo#\~/} ;;
  /*) ;;
  *) repo=./$repo ;;
esac
cd "$repo"
git_dir=$(git rev-parse --git-common-dir)

keys=$(ssh-add -L) || { echo 'No forwarded agent key. Check server agent-forwarding permissions.' >&2; exit 1; }
actual=$(printf '%s\n' "$keys" | awk '{print $1, $2}')
[ "$actual" = "$expected" ] || { echo 'Forwarded key does not match the selected YubiKey.' >&2; exit 1; }

# One include makes all three settings effective together; reruns replace the public key.
umask 077
name=yubikey-signing.gitconfig
tmp=$(mktemp "$git_dir/.$name.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
git config --file "$tmp" user.signingkey "key::$expected"
git config --file "$tmp" gpg.format ssh
git config --file "$tmp" commit.gpgsign true
mv -f -- "$tmp" "$git_dir/$name"
if ! git config --local --get-all include.path | grep -Fxq "$name"; then
  git config --local --add include.path "$name"
fi
if [ "$(git config user.signingkey)" != "key::$expected" ] ||
   [ "$(git config gpg.format)" != ssh ] || [ "$(git config --bool commit.gpgsign)" != true ]; then
  echo 'Another Git setting overrides repository signing. Inspect it with git config --show-origin --list.' >&2
  exit 1
fi
printf 'Git SSH signing enabled in %s\n' "$(pwd)"
