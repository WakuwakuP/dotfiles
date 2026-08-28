#!/usr/bin/env bash
# Interactive setup for machine-local credentials. Secret material is never
# copied into the dotfiles repository.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/ui.sh
. "${DOTFILES}/lib/ui.sh"

ASSUME_YES=0
SECRETS_BACKUP_DIR=""
LAST_BACKUP_PATH=""
SSH_STAGE=""
SSH_ORIGINAL_MOVED=0
GPG_SIGNING_KEY="339BA29AD11FE29A4E5AD8B6D6077D4B10C57FA3"

resolve_input_path() {
  local path="$1"

  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="${HOME}/${path#\~/}" ;;
    /*) ;;
    *) path="${PWD}/${path}" ;;
  esac

  realpath -m -- "$path"
}

backup_secret_path() {
  local path="$1"
  local relative="${path#$HOME/}"
  local backup

  if [[ -z "$SECRETS_BACKUP_DIR" ]]; then
    SECRETS_BACKUP_DIR="$(mktemp -d "${HOME}/.dotfiles-backup-$(date +%Y%m%d%H%M%S)-secrets.XXXXXX")"
    chmod 700 "$SECRETS_BACKUP_DIR"
  fi

  backup="${SECRETS_BACKUP_DIR}/${relative}"
  if [[ -e "$backup" || -L "$backup" ]]; then
    fail "backup destination already exists: ${backup}"
    return 1
  fi

  mkdir -p -m 700 "$(dirname "$backup")"
  LAST_BACKUP_PATH="$backup"
  if ! mv -T -- "$path" "$backup"; then
    LAST_BACKUP_PATH=""
    return 1
  fi
  info "backed up $path -> $backup"
}

setup_github_auth() {
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh is not installed; skip GitHub authentication"
    return 0
  fi

  if gh auth status --hostname github.com >/dev/null 2>&1; then
    skip "GitHub.com authentication is already configured"
    return 0
  fi

  info "Starting GitHub.com CLI authentication"
  gh auth login --hostname github.com
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    ok "GitHub.com authentication configured"
  else
    fail "GitHub.com authentication could not be verified"
    return 1
  fi
}

cleanup_ssh_transaction() {
  if [[ -n "$SSH_STAGE" && -d "$SSH_STAGE" ]]; then
    rm -rf -- "$SSH_STAGE"
  fi
  SSH_STAGE=""

  if [[ "$SSH_ORIGINAL_MOVED" == 1 ]]; then
    if [[ ! -e "${HOME}/.ssh" && ! -L "${HOME}/.ssh" ]]; then
      if [[ -e "$LAST_BACKUP_PATH" || -L "$LAST_BACKUP_PATH" ]] \
        && mv -T -- "$LAST_BACKUP_PATH" "${HOME}/.ssh"; then
        warn "restored the previous ${HOME}/.ssh"
      else
        warn "could not restore the previous ${HOME}/.ssh from ${LAST_BACKUP_PATH}"
      fi
    elif [[ -e "$LAST_BACKUP_PATH" || -L "$LAST_BACKUP_PATH" ]]; then
      warn "previous SSH files remain at ${LAST_BACKUP_PATH}"
    fi
  fi
  SSH_ORIGINAL_MOVED=0
}

setup_ssh() {
  local source_input source_dir

  source_input="$(ask_value "SSH backup directory (empty to skip)" "")"
  if [[ -z "$source_input" ]]; then
    skip "SSH restore"
    return 0
  fi

  source_dir="$(resolve_input_path "$source_input")"
  if [[ ! -d "$source_dir" ]]; then
    fail "SSH backup directory not found: ${source_dir}"
    return 1
  fi
  if [[ "$source_dir" == "$(realpath -m -- "${HOME}/.ssh")" ]]; then
    fail "SSH backup directory must differ from ${HOME}/.ssh"
    return 1
  fi
  if ! ask_yes "Restore ${source_dir} to ${HOME}/.ssh?" n; then
    skip "SSH restore"
    return 0
  fi

  SSH_STAGE="$(mktemp -d "${HOME}/.ssh-import.XXXXXX")"
  SSH_ORIGINAL_MOVED=0
  LAST_BACKUP_PATH=""
  trap cleanup_ssh_transaction EXIT
  trap 'cleanup_ssh_transaction; exit 130' INT TERM
  if ! cp -a "${source_dir}/." "$SSH_STAGE/" \
    || ! chmod 700 "$SSH_STAGE" \
    || ! find "$SSH_STAGE" -type d -exec chmod 700 {} + \
    || ! find "$SSH_STAGE" -type f -exec chmod 600 {} +; then
    cleanup_ssh_transaction
    trap - EXIT INT TERM
    fail "failed to prepare SSH backup"
    return 1
  fi

  if [[ -e "${HOME}/.ssh" || -L "${HOME}/.ssh" ]]; then
    SSH_ORIGINAL_MOVED=1
    if ! backup_secret_path "${HOME}/.ssh"; then
      SSH_ORIGINAL_MOVED=0
      cleanup_ssh_transaction
      trap - EXIT INT TERM
      return 1
    fi
  fi

  if ! mv -T -- "$SSH_STAGE" "${HOME}/.ssh"; then
    local original_was_moved="$SSH_ORIGINAL_MOVED"
    cleanup_ssh_transaction
    trap - EXIT INT TERM
    if [[ "$original_was_moved" == 0 ]]; then
      warn "SSH restore failed; no previous ${HOME}/.ssh existed"
    fi
    return 1
  fi

  SSH_STAGE=""
  SSH_ORIGINAL_MOVED=0
  trap - EXIT INT TERM
  ok "restored SSH files to ${HOME}/.ssh"
}

has_gpg_signing_key() {
  gpg --batch --with-colons --list-secret-keys "$GPG_SIGNING_KEY" 2>/dev/null \
    | awk -F: -v expected="$GPG_SIGNING_KEY" '
        $1 == "sec" || $1 == "ssb" { secret = 1; next }
        secret && $1 == "fpr" {
          if (toupper($10) == expected) found = 1
          secret = 0
        }
        END { exit !found }
      '
}

key_file_contains_signing_key() {
  local key_file="$1"

  gpg --batch --with-colons --import-options show-only --import "$key_file" 2>/dev/null \
    | awk -F: -v expected="$GPG_SIGNING_KEY" '
        $1 == "sec" || $1 == "ssb" { secret = 1; next }
        secret && $1 == "fpr" {
          if (toupper($10) == expected) found = 1
          secret = 0
        }
        END { exit !found }
      '
}

setup_gpg() {
  local key_input key_file

  if ! command -v gpg >/dev/null 2>&1; then
    warn "gpg is not installed; skip GPG private key import"
    return 0
  fi

  if has_gpg_signing_key; then
    skip "configured Git signing key is already available"
    return 0
  fi

  key_input="$(ask_value "GPG private key file (empty to skip)" "")"
  if [[ -z "$key_input" ]]; then
    skip "GPG private key import"
    return 0
  fi

  key_file="$(resolve_input_path "$key_input")"
  if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
    fail "GPG private key file is not readable: ${key_file}"
    return 1
  fi
  if ! key_file_contains_signing_key "$key_file"; then
    fail "file does not contain the configured Git signing key: ${GPG_SIGNING_KEY}"
    return 1
  fi
  if ! ask_yes "Import GPG private key from ${key_file}?" n; then
    skip "GPG private key import"
    return 0
  fi

  gpg --import "$key_file"
  if has_gpg_signing_key; then
    ok "configured Git signing key imported"
  else
    fail "GPG import completed, but the configured signing key is unavailable"
    return 1
  fi
}

main() {
  info "Machine-local credentials are not saved in the dotfiles repository"

  if ask_yes "Set up GitHub authentication?" n; then
    setup_github_auth
  else
    skip "GitHub authentication"
  fi

  if ask_yes "Restore SSH keys and config?" n; then
    setup_ssh
  else
    skip "SSH restore"
  fi

  if ask_yes "Import the GPG private key?" n; then
    setup_gpg
  else
    skip "GPG private key import"
  fi

  ok "credential setup finished"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
