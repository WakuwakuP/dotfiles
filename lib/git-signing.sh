# Write the selected backend to a machine-local file included by ~/.gitconfig.
set_git_signing() (
  set -eu
  local mode=$1 root=$2 dir="$HOME/.config/git" file key format tmp
  file="$dir/signing.gitconfig"
  case "$mode" in
    yubikey) format=ssh; key='~/.ssh/yubikey/active/identity' ;;
    gpg) format=openpgp; key=$(git config --file "$root/config/git/gitconfig" user.signingkey) ;;
    *) return 1 ;;
  esac
  mkdir -p "$dir"
  exec {signing_lock}<"$dir"
  flock -x "$signing_lock"
  tmp=$(mktemp "$dir/.signing.XXXXXXXX")
  trap 'rm -f -- "$tmp"' EXIT
  if [[ -f "$file" ]]; then cat "$file" > "$tmp"; fi
  if [[ $(git config --file "$tmp" --get gpg.ssh.program) == "$dir/yubikey-forwarded-signer" ]]; then
    git config --file "$tmp" --unset-all gpg.ssh.program
    if git config --file "$tmp" --get gpg.ssh.defaultKeyCommand >/dev/null; then
      git config --file "$tmp" --unset-all gpg.ssh.defaultKeyCommand
    fi
  fi
  git config --file "$tmp" --replace-all gpg.format "$format"
  git config --file "$tmp" --replace-all user.signingkey "$key"
  git config --file "$tmp" --replace-all commit.gpgsign true
  if [[ $mode == yubikey ]]; then
    git config --file "$tmp" --replace-all gpg.ssh.allowedSignersFile '~/.ssh/yubikey/allowed_signers'
  fi
  if ! cmp -s "$tmp" "$file"; then mv -T -- "$tmp" "$file"; fi
  # Standalone setup can also run with a global config that isn't linked by setup.sh.
  if [[ $(git config --global --includes --get gpg.format) != "$format" ||
        $(git config --global --includes --get user.signingkey) != "$key" ||
        $(git config --global --includes --bool --get commit.gpgsign) != true ||
        ( $mode == yubikey && $(git config --global --includes --path --get gpg.ssh.allowedSignersFile) != "$HOME/.ssh/yubikey/allowed_signers" ) ]]; then
    git config --global --add include.path '~/.config/git/signing.gitconfig'
  fi
)
