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
if [ -r /usr/share/bash-completion/completions/ssh ]; then
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

  _ssh "$@"
}

complete -F _ssh_no_slow_remote_command_completion ssh
