# Replace the default prompt when starship is on PATH.
# powerline-shell is Python and costs ~150ms per prompt on WSL.

if ! command -v starship >/dev/null 2>&1; then
  return 0
fi

if [[ $TERM == linux ]]; then
  return 0
fi

eval "$(starship init bash)"

# starship_precmd_user_func must be a variable holding the function name.
# starship_precmd sets STARSHIP_CMD_STATUS, then runs this, then `starship prompt`.
_dotfiles_export_starship_status() {
  export STARSHIP_CMD_STATUS
}
starship_precmd_user_func=_dotfiles_export_starship_status
