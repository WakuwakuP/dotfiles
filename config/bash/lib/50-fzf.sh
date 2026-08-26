# fzf helpers and key bindings.
# Matches Windows PowerShell: fzf --layout=reverse, ghq preview via bat / lsd.

if ! is_exists fzf; then
  return 0
fi

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---layout=reverse}"

_fzf_ghq_preview_cmd() {
  local bat_cmd tree_cmd
  if is_exists bat; then
    bat_cmd='bat --color=always --line-range :50'
  elif is_exists batcat; then
    bat_cmd='batcat --color=always --line-range :50'
  else
    bat_cmd='head -n 50'
  fi

  if is_exists lsd; then
    tree_cmd='lsd --color always --tree --depth 1'
  else
    tree_cmd='ls --color=always -1'
  fi

  printf 'if [ -f {}/README.md ]; then %s {}/README.md; else %s {}; fi' "$bat_cmd" "$tree_cmd"
}

_fzf_select_ghq() {
  ghq list --full-path | fzf --layout=reverse --preview "$(_fzf_ghq_preview_cmd)" --query "${1:-}"
}

# Same as PowerShell `g`: pick a ghq repo and cd.
g() {
  local selected
  selected="$(_fzf_select_ghq "$*")" || return
  if [[ -n "$selected" ]]; then
    cd "$selected" || return
  fi
}

fzf-ghql() {
  local selected_file
  selected_file="$(_fzf_select_ghq "${READLINE_LINE:-}")" || return
  if [[ -n "$selected_file" && -t 1 ]]; then
    echo "${selected_file}"
    cd "${selected_file}" || return
    pwd
    READLINE_LINE=
    READLINE_POINT=0
  fi
}

fzf-ssh() {
  local selected_host
  [[ -r "${HOME}/.ssh/config" ]] || return 1
  selected_host=$(awk '
    tolower($1)=="host" {
      for (i=2; i<=NF; i++) {
        if ($i !~ "[*?]") {
          print $i
        }
      }
    }
  ' ~/.ssh/config | sort | fzf --query "${READLINE_LINE:-}") || return
  if [[ -n "$selected_host" ]]; then
    # Functions skip aliases; honor `alias ssh=tmux_ssh` inside tmux.
    eval "${BASH_ALIASES[ssh]:-command ssh} ${selected_host@Q}"
  fi
}

fzf-history() {
  local tac selected
  if command -v gtac >/dev/null 2>&1; then
    tac=gtac
  elif command -v tac >/dev/null 2>&1; then
    tac=tac
  else
    tac="tail -r"
  fi
  selected=$(HISTTIMEFORMAT= history | $tac | sed -e 's/^\s*[0-9]\+\s\+//' | awk '!a[$0]++' | fzf --query "$READLINE_LINE") || return
  if [[ -n "$selected" ]]; then
    READLINE_LINE=$selected
    READLINE_POINT=${#READLINE_LINE}
  fi
}

fzf-buffer() {
  local select
  [[ -n "$READLINE_LINE" ]] || return
  select=$(eval "$READLINE_LINE" | fzf) || return
  if [[ -n "$select" ]]; then
    READLINE_LINE="$READLINE_LINE$select"
    READLINE_POINT=${#READLINE_LINE}
  fi
}

fzf-select-tmux-session() {
  if [[ -n "${TMUX:-}" ]]; then
    echo 'Do not use this command in a tmux session.'
    return 1
  fi

  local session
  session="$(tmux list-sessions | fzf | cut -d : -f 1)" || return
  if [[ -n "$session" ]]; then
    tmux a -t "$session"
  fi
}

bind -x '"\C-g": fzf-ghql'
bind -x '"\C-a": fzf-ssh'
bind -x '"\C-r": fzf-history'
bind -x '"\C-l": fzf-buffer'
bind -x '"\C-t": fzf-select-tmux-session'
