#!/usr/bin/env bash
# Bootstrap: clone this repo to ~/.dotfiles (unless already running from a checkout)
# and launch the interactive setup.
set -euo pipefail

REPO="${REPO:-https://github.com/WakuwakuP/dotfiles.git}"
DOTPATH="${DOTPATH:-$HOME/.dotfiles}"

run_setup() {
  local setup="$1"
  shift
  local arg

  for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" || "$arg" == "-h" || "$arg" == "--help" ]]; then
      exec "$setup" "$@"
    fi
  done

  if ! { : </dev/tty; } 2>/dev/null; then
    echo "Interactive setup requires a terminal. Run again from a terminal or pass --yes." >&2
    exit 1
  fi
  exec "$setup" "$@" </dev/tty
}

self="${BASH_SOURCE[0]:-}"
if [[ -n "$self" && -f "$self" ]]; then
  here="$(cd "$(dirname "$(readlink -f "$self")")" && pwd)"
  if [[ -f "${here}/setup.sh" && -d "${here}/config" ]]; then
    run_setup "${here}/setup.sh" "$@"
  fi
fi

if [[ -d "${DOTPATH}/.git" ]]; then
  git -C "${DOTPATH}" pull --ff-only
else
  git clone --recursive "${REPO}" "${DOTPATH}"
fi

run_setup "${DOTPATH}/setup.sh" "$@"
