# Replace the default prompt when powerline-shell is on PATH.

if command -v powerline-shell >/dev/null 2>&1; then
  _update_ps1() {
    PS1="$(powerline-shell $?)"
  }

  if [[ $TERM != linux && ! ${PROMPT_COMMAND:-} =~ _update_ps1 ]]; then
    PROMPT_COMMAND="_update_ps1; ${PROMPT_COMMAND:-}"
  fi
fi
