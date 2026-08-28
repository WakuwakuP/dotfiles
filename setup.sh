#!/usr/bin/env bash
# Interactive restore of this machine's customizations.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/ui.sh
. "${DOTFILES}/lib/ui.sh"

ASSUME_YES=0
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup-$(date +%Y%m%d%H%M%S)}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Restore WakuwakuP/dotfiles onto this machine.

Options:
  -y, --yes     Run steps 1-7 non-interactively; skip credentials
  -h, --help    Show this help

Steps (each can be skipped):
  1. Symlink config files (existing files are backed up)
  2. Install apt packages: tmux fzf bat gh git gpg
  3. Install ghq and configure its root directory
  4. Install tmux plugin manager (tpm + tmux-sensible)
  5. Install win32yank.exe (WSL clipboard)
  6. Install starship (fast prompt; replaces powerline-shell)
  7. Symlink Cursor user rules to ~/.cursor/rules
  8. Set up GitHub, SSH, and GPG credentials (interactive only)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

is_wsl() {
  # Docker Desktop's Linux VM also reports "microsoft" in /proc/version.
  # Require an actual WSL interop surface, not just a Microsoft kernel.
  [[ -n "${WSL_DISTRO_NAME:-}" && -e /proc/sys/fs/binfmt_misc/WSLInterop ]]
}

backup_path() {
  local dest="$1"
  local rel="${dest#$HOME/}"
  local target="${BACKUP_DIR}/${rel}"
  mkdir -p "$(dirname "$target")"
  mv "$dest" "$target"
  info "backed up $dest -> $target"
}

link_file() {
  local dest="$1"
  local src="$2"

  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink -f "$dest" || true)"
    local expected
    expected="$(readlink -f "$src")"
    if [[ "$current" == "$expected" ]]; then
      skip "already linked $dest"
      return 0
    fi
    backup_path "$dest"
  elif [[ -e "$dest" ]]; then
    backup_path "$dest"
  fi

  ln -s "$src" "$dest"
  ok "linked $dest -> $src"
}

step_links() {
  info "Link config files from ${DOTFILES}"
  link_file "$HOME/.bashrc" "${DOTFILES}/config/bash/bashrc"
  link_file "$HOME/.profile" "${DOTFILES}/config/bash/profile"
  link_file "$HOME/.bash_logout" "${DOTFILES}/config/bash/bash_logout"
  link_file "$HOME/.gitconfig" "${DOTFILES}/config/git/gitconfig"
  link_file "$HOME/.tmux.conf" "${DOTFILES}/config/tmux/tmux.conf"
  link_file "$HOME/.nanorc" "${DOTFILES}/config/nano/nanorc"
  link_file "$HOME/.config/gh/config.yml" "${DOTFILES}/config/gh/config.yml"
  link_file "$HOME/.config/starship.toml" "${DOTFILES}/config/starship/starship.toml"

  if [[ -L "$HOME/.peco" ]]; then
    local peco_link
    peco_link="$(readlink "$HOME/.peco" || true)"
    if [[ "$peco_link" == "${DOTFILES}/config/peco" || "$peco_link" == *"/config/peco" ]]; then
      rm "$HOME/.peco"
      ok "removed leftover peco symlink"
    fi
  fi
}

ensure_universe() {
  if grep -RqsE '(^|[[:space:]])universe([[:space:]]|$)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    return 0
  fi
  if command -v add-apt-repository >/dev/null 2>&1; then
    sudo add-apt-repository -y universe
  fi
}

install_gh() {
  if command -v gh >/dev/null 2>&1; then
    skip "gh already installed"
    return 0
  fi
  if apt-cache show gh >/dev/null 2>&1; then
    sudo apt-get install -y gh
    return 0
  fi

  info "gh is not in apt; adding the GitHub CLI apt repository"
  sudo apt-get install -y curl ca-certificates
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gh
}

step_packages() {
  info "Install apt packages: tmux fzf bat gh git gpg curl"
  sudo apt-get update
  ensure_universe
  sudo apt-get install -y tmux fzf bat git gpg curl ca-certificates
  if apt-cache show lsd >/dev/null 2>&1; then
    sudo apt-get install -y lsd
  else
    skip "lsd is not in apt; ghq preview will fall back to ls"
  fi
  install_gh
  ok "apt packages installed"
}

resolve_user_path() {
  local path="$1"

  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="${HOME}/${path#\~/}" ;;
    /*) ;;
    *) path="${HOME}/${path}" ;;
  esac

  realpath -m -- "$path"
}

step_ghq() {
  local config_file="${HOME}/.config/git/ghq.gitconfig"
  local default_root="${HOME}/ghq"
  local ghq_root

  if command -v ghq >/dev/null 2>&1; then
    skip "ghq already installed ($(command -v ghq))"
  elif command -v apt-get >/dev/null 2>&1 && apt-cache show ghq >/dev/null 2>&1; then
    sudo apt-get install -y ghq
    ok "ghq installed via apt"
  elif command -v go >/dev/null 2>&1; then
    go install github.com/x-motemen/ghq@latest
    ok "ghq installed via go"
  else
    local tmp arch asset url binary
    case "$(uname -m)" in
      x86_64|amd64) arch=amd64 ;;
      aarch64|arm64) arch=arm64 ;;
      *) fail "unsupported arch for ghq: $(uname -m)"; return 1 ;;
    esac
    asset="ghq_linux_${arch}.zip"
    tmp="$(mktemp -d)"
    url="$(curl -fsSL https://api.github.com/repos/x-motemen/ghq/releases/latest \
      | grep -oE "https://[^\"]+/${asset}" | head -n1 || true)"
    if [[ -z "$url" ]]; then
      url="https://github.com/x-motemen/ghq/releases/latest/download/${asset}"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
      sudo apt-get install -y python3
    fi
    info "downloading ${url}"
    curl -fsSL "$url" -o "${tmp}/ghq.zip"
    python3 - "${tmp}" <<'PY'
import sys, zipfile
from pathlib import Path
tmp = Path(sys.argv[1])
zipfile.ZipFile(tmp / "ghq.zip").extractall(tmp)
PY
    binary="$(find "$tmp" -type f -name ghq | head -n1 || true)"
    if [[ -z "$binary" ]]; then
      fail "ghq binary missing from release archive"
      rm -rf "$tmp"
      return 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "$binary" "${HOME}/.local/bin/ghq"
    rm -rf "$tmp"
    ok "ghq installed to ~/.local/bin/ghq"
  fi

  if [[ -f "$config_file" ]]; then
    default_root="$(git config --file "$config_file" --get ghq.root 2>/dev/null || printf '%s\n' "$default_root")"
  fi

  ghq_root="$(ask_value "ghq root directory" "$default_root")"
  ghq_root="$(resolve_user_path "$ghq_root")"

  if [[ -e "$ghq_root" && ! -d "$ghq_root" ]]; then
    fail "ghq root exists but is not a directory: ${ghq_root}"
    return 1
  elif [[ -d "$ghq_root" ]]; then
    skip "${ghq_root} already exists"
  elif ask_yes "Create ghq root ${ghq_root}?" y; then
    mkdir -p "$ghq_root"
    ok "created ${ghq_root}"
  else
    skip "left ${ghq_root} uncreated"
  fi

  mkdir -p "$(dirname "$config_file")"
  git config --file "$config_file" --replace-all ghq.root "$ghq_root"
  ok "configured ghq root: ${ghq_root}"
}

step_tpm() {
  local tpm_dir="${HOME}/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir/.git" ]]; then
    skip "tpm already installed"
  else
    mkdir -p "${HOME}/.tmux/plugins"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"
    ok "cloned tpm"
  fi

  if [[ -x "${tpm_dir}/bin/install_plugins" ]]; then
    "${tpm_dir}/bin/install_plugins"
    ok "tmux plugins installed"
  else
    warn "tpm install helper missing; open tmux and press prefix + I"
  fi
}

step_win32yank() {
  if command -v win32yank.exe >/dev/null 2>&1; then
    skip "win32yank.exe already on PATH"
    return 0
  fi

  if ! is_wsl; then
    warn "not WSL; skip win32yank (tmux copy/paste expects it on WSL)"
    return 0
  fi

  local tmp zip dest
  tmp="$(mktemp -d)"
  zip="${tmp}/win32yank.zip"
  dest="${HOME}/.local/bin/win32yank.exe"
  mkdir -p "${HOME}/.local/bin"
  curl -fsSL -o "$zip" https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip
  python3 - <<PY
import zipfile
z = zipfile.ZipFile("${zip}")
z.extract("win32yank.exe", "${tmp}")
PY
  install -m 0755 "${tmp}/win32yank.exe" "$dest"
  rm -rf "$tmp"
  ok "installed $dest"
}

step_starship() {
  if command -v starship >/dev/null 2>&1; then
    skip "starship already installed ($(command -v starship))"
  else
    mkdir -p "${HOME}/.local/bin"
    info "Install starship to ~/.local/bin"
    if curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "${HOME}/.local/bin"; then
      ok "starship installed to ~/.local/bin/starship"
    else
      fail "starship install failed"
      return 1
    fi
  fi

  if command -v powerline-shell >/dev/null 2>&1; then
    info "powerline-shell is unused now (slow Python prompt). Remove with: pip3 uninstall --break-system-packages powerline-shell"
  fi
}

step_cursor_rules() {
  local src="${DOTFILES}/cursor/rules"
  local dest="${HOME}/.cursor/rules"
  mkdir -p "$dest"
  local file
  for file in "${src}"/*.mdc; do
    [[ -e "$file" ]] || continue
    local name
    name="$(basename "$file")"
    if [[ -e "${dest}/${name}" ]]; then
      if [[ "$(readlink -f "${dest}/${name}" 2>/dev/null || true)" == "$(readlink -f "$file")" ]]; then
        skip "already linked ${dest}/${name}"
        continue
      fi
      backup_path "${dest}/${name}"
    fi
    ln -s "$file" "${dest}/${name}"
    ok "linked ${dest}/${name}"
  done
}

print_cursor_plugins() {
  info "Enable these Cursor plugins manually:"
  sed -n '1,80p' "${DOTFILES}/cursor/plugins.md"
}

print_secrets_note() {
  cat <<EOF

${YELLOW}Machine-local credentials are not stored in this repository:${RESET}
  - SSH private keys and ~/.ssh/config hosts
  - GPG private key ${CYAN}339BA29AD11FE29A4E5AD8B6D6077D4B10C57FA3${RESET} (commits are signed)
  - gh authentication token

Run the credential setup again with: ${CYAN}bash ${DOTFILES}/setup-secrets.sh${RESET}
Reload the shell with: ${CYAN}exec bash -l${RESET}
EOF
}

main() {
  info "DOTFILES=${DOTFILES}"
  info "non-interactive=${ASSUME_YES}"

  if ask_yes "1/8 Symlink config files?" y; then
    step_links
  else
    skip "symlinks"
  fi

  if ask_yes "2/8 Install apt packages (tmux fzf bat gh git gpg)?" y; then
    step_packages
  else
    skip "apt packages"
  fi

  if ask_yes "3/8 Install ghq and configure its root directory?" y; then
    step_ghq
  else
    skip "ghq"
  fi

  if ask_yes "4/8 Install tmux plugins (tpm + tmux-sensible)?" y; then
    step_tpm
  else
    skip "tpm"
  fi

  if ask_yes "5/8 Install win32yank.exe for WSL clipboard?" y; then
    step_win32yank
  else
    skip "win32yank"
  fi

  if ask_yes "6/8 Install starship (replaces powerline-shell)?" y; then
    step_starship
  else
    skip "starship"
  fi

  if ask_yes "7/8 Symlink Cursor user rules to ~/.cursor/rules?" y; then
    step_cursor_rules
  else
    skip "cursor rules"
  fi

  if [[ "$ASSUME_YES" == 1 ]]; then
    skip "credential setup in non-interactive mode"
  elif ask_yes "8/8 Set up GitHub, SSH, and GPG credentials?" n; then
    bash "${DOTFILES}/setup-secrets.sh"
  else
    skip "credentials"
  fi

  print_cursor_plugins
  print_secrets_note
  ok "setup finished"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
