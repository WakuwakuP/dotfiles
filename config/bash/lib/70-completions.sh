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
