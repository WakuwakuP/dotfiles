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

complete_line() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMP_LINE="${COMP_WORDS[*]}"
  COMP_POINT=${#COMP_LINE}
  COMPREPLY=()
  # Completion helpers run in interactive shells without errexit.
  _ssh_no_slow_remote_command_completion ssh "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}" || return $?
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
unset -f _ssh _init_completion _count_args
set -o posix
source "$ROOT/config/bash/lib/70-completions.sh"
if complete -p ssh 2>/dev/null; then
  echo 'FAIL Wrapper registered without bash-completion' >&2
  exit 1
fi
echo 'OK   No wrapper registered without bash-completion'
