# peco helpers and key bindings.

peco-ghql() {
  local selected_file
  selected_file=$(ghq list --full-path | peco --query "${LBUFFER:-}")
  if [ -n "$selected_file" ] && [ -t 1 ]; then
    echo "${selected_file}"
    cd "${selected_file}" || return
    pwd
  fi
}

peco-ssh() {
  local selected_host
  selected_host=$(awk '
    tolower($1)=="host" {
      for (i=2; i<=NF; i++) {
        if ($i !~ "[*?]") {
          print $i
        }
      }
    }
  ' ~/.ssh/config | sort | peco --query "${LBUFFER:-}")
  if [ -n "$selected_host" ]; then
    ssh "${selected_host}"
  fi
}

peco-history() {
  local tac
  if command -v gtac >/dev/null 2>&1; then
    tac=gtac
  elif command -v tac >/dev/null 2>&1; then
    tac=tac
  else
    tac="tail -r"
  fi
  READLINE_LINE=$(HISTTIMEFORMAT= history | $tac | sed -e 's/^\s*[0-9]\+\s\+//' | awk '!a[$0]++' | peco --query "$READLINE_LINE")
  READLINE_POINT=${#READLINE_LINE}
}

peco-buffer() {
  local select
  select=$(eval "$READLINE_LINE" | peco --query "${LBUFFER:-}")
  READLINE_LINE="$READLINE_LINE$select"
  READLINE_POINT=${#READLINE_LINE}
}

peco-select-tmux-session() {
  if [ -n "${TMUX:-}" ]; then
    echo 'Do not use this command in a tmux session.'
    return 1
  fi

  local session
  session="$(tmux list-sessions | peco | cut -d : -f 1)"
  if [ -n "$session" ]; then
    tmux a -t "$session"
  fi
}

bind -x '"\C-g": peco-ghql'
bind -x '"\C-a": peco-ssh'
bind -x '"\C-r": peco-history'
bind -x '"\C-l": peco-buffer'
bind -x '"\C-t": peco-select-tmux-session'
