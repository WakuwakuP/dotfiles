#!/usr/bin/env bash
# Standalone regression checks; requires bash-completion and openssh-client.
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HOME="$(mktemp -d)"
trap 'rm -rf -- "$HOME"' EXIT
mkdir -p "$HOME/.ssh"
printf 'Host _dotfiles_completion_test\n  HostName 192.0.2.1\n' > "$HOME/.ssh/config"

source "$ROOT/config/bash/lib/70-completions.sh"
[[ $(complete -p ssh) == *'-F _ssh_no_slow_remote_command_completion ssh' ]]
[[ $(complete -p yubikey-ssh) == *'-F _yubikey_ssh_completion yubikey-ssh' ]]

complete_line() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMP_LINE="${COMP_WORDS[*]}"
  COMP_POINT=${#COMP_LINE}
  COMPREPLY=()
  # Completion helpers run in interactive shells without errexit.
  local fn=_ssh_no_slow_remote_command_completion
  if [[ $1 == yubikey-ssh ]]; then fn=_yubikey_ssh_completion; fi
  "$fn" "$1" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}" || return $?
}

complete_line ssh _
[[ " ${COMPREPLY[*]} " == *' _dotfiles_completion_test '* ]]
echo 'OK   SSH host completion with installed bash-completion'

complete_line ssh -o StrictHostKeyChecking=
[[ " ${COMPREPLY[*]} " == *' ask '* ]]
echo 'OK   SSH option completion'

complete_line ssh _dotfiles_completion_test ec
[[ ${#COMPREPLY[@]} == 0 ]]
echo 'OK   SSH remote-command completion stays disabled'

printf 'Include %s\n' "$HOME/.ssh/dev.conf" >> "$HOME/.ssh/config"
printf 'Host _yk_devbox\n' > "$HOME/.ssh/dev.conf"
printf '_yk_known ssh-ed25519 AAAA\n' > "$HOME/.ssh/known_hosts"
complete_line ssh _yk_
[[ " ${COMPREPLY[*]} " == *' _yk_devbox '* && " ${COMPREPLY[*]} " == *' _yk_known '* ]]
ssh_hosts=("${COMPREPLY[@]}")
for action in --on --off; do
  complete_line yubikey-ssh forward "$action" _yk_
  [[ ${COMPREPLY[*]} == "${ssh_hosts[*]}" ]]
done
for subcommand in host forward doctor; do
  complete_line yubikey-ssh "$subcommand" _yk_
  [[ ${COMPREPLY[*]} == "${ssh_hosts[*]}" ]]
done
complete_line yubikey-ssh forward --repo src/app _yk_
[[ ${COMPREPLY[*]} == "${ssh_hosts[*]}" ]]
complete_line yubikey-ssh host --install git@_yk_dev
[[ ${COMPREPLY[*]} == git@_yk_devbox ]]
complete_line yubikey-ssh forward --o
[[ " ${COMPREPLY[*]} " == *' --on '* && " ${COMPREPLY[*]} " == *' --off '* ]]
complete_line yubikey-ssh forward --list ''
[[ ${#COMPREPLY[@]} == 0 ]]
complete_line yubikey-ssh forward --repo _yk_
[[ ${#COMPREPLY[@]} == 0 ]]
echo 'OK   YubiKey host arguments use SSH completion, including user@host'

# Exercise dispatch on both naming schemes without requiring two installations.
_ssh() { COMPREPLY=(legacy); }
_comp_cmd_ssh() { COMPREPLY=(modern); }
complete_line ssh _
[[ ${COMPREPLY[*]} == modern ]]
unset -f _comp_cmd_ssh
complete_line ssh _
[[ ${COMPREPLY[*]} == legacy ]]
echo 'OK   Modern and legacy SSH completion dispatch'

complete -r ssh
complete -r yubikey-ssh
unset -f _ssh _init_completion _count_args
set -o posix
source "$ROOT/config/bash/lib/70-completions.sh"
if complete -p ssh 2>/dev/null; then
  echo 'FAIL Wrapper registered without bash-completion' >&2
  exit 1
fi
if complete -p yubikey-ssh 2>/dev/null; then exit 1; fi
echo 'OK   No wrapper registered without bash-completion'
