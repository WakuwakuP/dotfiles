#!/usr/bin/env bash
# Bootstrap: clone this repo to ~/.dotfiles (unless already running from a checkout)
# and launch the interactive setup.
set -euo pipefail

REPO="${REPO:-https://github.com/WakuwakuP/dotfiles.git}"
DOTPATH="${DOTPATH:-$HOME/.dotfiles}"

self="${BASH_SOURCE[0]:-}"
if [[ -n "$self" && -f "$self" ]]; then
  here="$(cd "$(dirname "$(readlink -f "$self")")" && pwd)"
  if [[ -f "${here}/setup.sh" && -d "${here}/config" ]]; then
    exec "${here}/setup.sh" "$@"
  fi
fi

if [[ -d "${DOTPATH}/.git" ]]; then
  git -C "${DOTPATH}" pull --ff-only
else
  git clone --recursive "${REPO}" "${DOTPATH}"
fi

exec "${DOTPATH}/setup.sh" "$@"
