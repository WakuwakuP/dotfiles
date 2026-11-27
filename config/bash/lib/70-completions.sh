# bash-completion, with a faster ssh completer.

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    # shellcheck source=/dev/null
    . /etc/bash_completion
  fi
fi

# Avoid slow `compgen -c` from bash-completion's ssh remote-command completion.
if declare -F _init_completion >/dev/null && [ -r /usr/share/bash-completion/completions/ssh ]; then
  # shellcheck source=/dev/null
  . /usr/share/bash-completion/completions/ssh
fi

_ssh_no_slow_remote_command_completion() {
  local cur prev words cword args
  _init_completion -n : || return

  _count_args

  if ((args > 1)) && [[ $cur != -* ]]; then
    COMPREPLY=()
    return 0
  fi

  # bash-completion 2.12+ uses namespaced completion functions.
  if declare -F _comp_cmd_ssh >/dev/null; then
    _comp_cmd_ssh "$@"
  elif declare -F _ssh >/dev/null; then
    _ssh "$@"
  fi
}

if declare -F _init_completion >/dev/null && declare -F _count_args >/dev/null \
  && { declare -F _comp_cmd_ssh >/dev/null || declare -F _ssh >/dev/null; }; then
  complete -F _ssh_no_slow_remote_command_completion ssh
fi

_yubikey_ssh_completion() {
  local cur prev words cword choices
  _init_completion -n : || return
  case "$cword:${words[1]-}:${words[2]-}" in
    1:*) choices='setup use host forward doctor' ;;
    2:use:*|2:setup:*) choices='nano nfc' ;;
    3:setup:nano|3:setup:nfc) choices='create import' ;;
    2:forward:-*) choices='--on --off --list --repo' ;;
    2:host:-*) choices='--install' ;;
    2:forward:*|2:host:*|2:doctor:*|3:forward:--on|3:forward:--off|3:host:--install|4:forward:--repo)
      # Use the same alias and known-host sources as ssh on both bash-completion APIs.
      if declare -F _comp_compgen_known_hosts >/dev/null; then
        _comp_compgen_known_hosts -a -- "$cur"
      else
        _known_hosts_real -a -- "$cur"
      fi
      return ;;
    *) return 0 ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W "$choices" -- "$cur")
}

if declare -F _init_completion >/dev/null \
  && { declare -F _comp_compgen_known_hosts >/dev/null || declare -F _known_hosts_real >/dev/null; }; then
  complete -F _yubikey_ssh_completion yubikey-ssh
fi
