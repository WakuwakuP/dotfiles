# Sent to sh -s, followed by a call passing the signer source on stdin.
set -eu
install_signer() {
  umask 077
  dir="$HOME/.config/git"
  file="$dir/signing.gitconfig"
  signer="$dir/yubikey-forwarded-signer"
  mkdir -p "$dir"
  exec 9<"$dir"
  flock -x 9
  stage=$(mktemp -d "$dir/.forward-signing.XXXXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  cat > "$stage/signer"
  chmod 700 "$stage/signer"
  "$stage/signer" --public-key >/dev/null
  if [ -f "$file" ]; then cat "$file" > "$stage/config"; fi
  git config --file "$stage/config" --replace-all gpg.format ssh
  git config --file "$stage/config" --replace-all commit.gpgsign true
  git config --file "$stage/config" --replace-all gpg.ssh.program "$signer"
  default_key_command="sh -c 'exec \"\$HOME/.config/git/yubikey-forwarded-signer\" --public-key'"
  git config --file "$stage/config" --replace-all gpg.ssh.defaultKeyCommand "$default_key_command"
  mv -fT -- "$stage/signer" "$signer"
  mv -fT -- "$stage/config" "$file"
  # The dotfiles gitconfig already includes this file last. Standalone or
  # older setups may need a trailing include to override prior GPG settings.
  if [ "$(git config --global --includes --get gpg.ssh.program)" != "$signer" ] ||
     [ "$(git config --global --includes --get gpg.format)" != ssh ] ||
     [ "$(git config --global --includes --bool --get commit.gpgsign)" != true ] ||
     [ "$(git config --global --includes --get gpg.ssh.defaultKeyCommand)" != "$default_key_command" ]; then
    git config --global --add include.path '~/.config/git/signing.gitconfig'
  fi
  printf 'Forwarded Git SSH signing configured for %s\n' "$HOME"
}
