# Auto-attach tmux, and color SSH panes by hostname while inside tmux.

t() {
  tmux new-session -s "$(basename "$(pwd)")"
}

tmux_automatically_attach_session() {
  if is_screen_or_tmux_running; then
    ! is_exists tmux && return 1

    if is_tmux_running; then
      echo "${fg_bold[red]:-} _____ __  __ _   ___  __ ${reset_color:-}"
      echo "${fg_bold[red]:-}|_   _|  \/  | | | \ \/ / ${reset_color:-}"
      echo "${fg_bold[red]:-}  | | | |\/| | | | |\  /  ${reset_color:-}"
      echo "${fg_bold[red]:-}  | | | |  | | |_| |/  \  ${reset_color:-}"
      echo "${fg_bold[red]:-}  |_| |_|  |_|\___//_/\_\ ${reset_color:-}"
    elif is_screen_running; then
      echo "This is on screen."
    fi
    return 0
  fi

  if ! shell_has_started_interactively || is_ssh_running; then
    return 0
  fi

  if ! is_exists tmux; then
    echo 'Error: tmux command not found' >&2
    return 1
  fi

  if tmux has-session >/dev/null 2>&1 && tmux list-sessions | grep -qE '.*]$'; then
    tmux list-sessions
    echo -n "Tmux: attach? (y/N/num) "
    read -r
    if [[ "$REPLY" =~ ^[Yy]$ ]] || [[ "$REPLY" == '' ]]; then
      if tmux attach-session; then
        echo "$(tmux -V) attached session"
        return 0
      fi
    elif [[ "$REPLY" =~ ^[0-9]+$ ]]; then
      if tmux attach -t "$REPLY"; then
        echo "$(tmux -V) attached session"
        return 0
      fi
    fi
  fi

  if is_osx && is_exists reattach-to-user-namespace; then
    local tmux_config
    tmux_config=$(cat "$HOME/.tmux.conf" <(echo 'set-option -g default-command "reattach-to-user-namespace -l $SHELL"'))
    tmux -f <(echo "$tmux_config") new-session && echo "$(tmux -V) created new session supported OS X"
  else
    tmux new-session && echo "tmux created new session"
  fi
}

tmux_automatically_attach_session

if [ -n "${TMUX:-}" ]; then
  # Readable white-on-dark backgrounds, chosen from the SSH hostname.
  DARK_COLORS=(17 18 19 22 23 24 52 53 54 58 59 60 88 89 90 234 235 236 237)

  _tmux_color_for_host() {
    local hash index
    hash=$(echo -n "$1" | cksum | awk '{print $1}')
    index=$((hash % ${#DARK_COLORS[@]}))
    echo "${DARK_COLORS[$index]}"
  }

  tmux_ssh() {
    local color
    color="$(_tmux_color_for_host "$1")"
    tmux new-window -n "ssh:$1" "exec ssh $*"
    tmux select-pane -P "bg=colour${color},fg=white"
  }
  alias ssh=tmux_ssh

  tmux_pane_ssh() {
    local color
    color="$(_tmux_color_for_host "$1")"
    tmux split-pane -h -c "ssh:$1" "exec ssh $*"
    tmux select-pane -P "bg=colour${color},fg=white"
  }
  alias pssh=tmux_pane_ssh

  ph() {
    tmux split-pane -h "exec $*"
  }

  ide() {
    tmux split-window -h
    tmux split-window -v
    tmux resize-pane -D 15
    tmux select-pane -t 1
    tmux split-window -v
    tmux select-pane -t 1
  }
fi
