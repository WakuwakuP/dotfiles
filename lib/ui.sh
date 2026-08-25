# shellcheck shell=bash

ESC=$'\033'
RESET="${ESC}[0m"
GREEN="${ESC}[32m"
CYAN="${ESC}[36m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"
BLUE="${ESC}[34m"

msg() { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
ok() { msg "${GREEN}OK${RESET} $*"; }
info() { msg "${CYAN}INFO${RESET} $*"; }
skip() { msg "${BLUE}SKIP${RESET} $*"; }
warn() { msg "${YELLOW}WARN${RESET} $*"; }
fail() { msg "${RED}FAIL${RESET} $*" >&2; }

ask_yes() {
  local prompt="$1"
  local default="${2:-y}"
  local reply

  if [[ "${ASSUME_YES:-0}" == 1 ]]; then
    return 0
  fi

  if [[ "$default" == y ]]; then
    printf '%s [Y/n] ' "$prompt"
  else
    printf '%s [y/N] ' "$prompt"
  fi

  read -r reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}
