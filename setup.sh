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
  -y, --yes     Accept every prompt (non-interactive)
  -h, --help    Show this help

Steps (each can be skipped):
  1. Symlink config files (existing files are backed up)
  2. Install apt packages: tmux peco gh git gpg
  3. Install ghq and ensure ghq root /src
  4. Install tmux plugin manager (tpm + tmux-sensible)
  5. Install win32yank.exe (WSL clipboard)
  6. Install powerline-shell
  7. Copy Cursor user rules to ~/.cursor/rules
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
  link_file "$HOME/.peco" "${DOTFILES}/config/peco"
  link_file "$HOME/.config/gh/config.yml" "${DOTFILES}/config/gh/config.yml"
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
  info "Install apt packages: tmux peco gh git gpg curl"
  sudo apt-get update
  ensure_universe
  sudo apt-get install -y tmux peco git gpg curl ca-certificates
  install_gh
  ok "apt packages installed"
}

step_ghq() {
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

  if [[ -d /src ]]; then
    skip "/src already exists"
  else
    if ask_yes "Create ghq root /src (needs sudo)?" y; then
      sudo mkdir -p /src
      sudo chown "${USER}:${USER}" /src
      ok "created /src"
    else
      skip "left /src uncreated. gitconfig still has ghq.root=/src"
    fi
  fi
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

step_powerline() {
  if command -v powerline-shell >/dev/null 2>&1; then
    skip "powerline-shell already installed"
    return 0
  fi

  if ! command -v pip3 >/dev/null 2>&1; then
    sudo apt-get install -y python3-pip
  fi
  if pip3 install --user --break-system-packages powerline-shell; then
    ok "powerline-shell installed"
    return 0
  fi
  fail "powerline-shell install failed"
  return 1
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

${YELLOW}Not installed (secrets / machine-local):${RESET}
  - SSH private keys and ~/.ssh/config hosts
  - GPG private key ${CYAN}339BA29AD11FE29A4E5AD8B6D6077D4B10C57FA3${RESET} (commits are signed)
  - AWS / Azure credentials
  - gh auth token (run: ${CYAN}gh auth login${RESET})

Reload the shell with: ${CYAN}exec bash -l${RESET}
EOF
}

main() {
  info "DOTFILES=${DOTFILES}"
  info "non-interactive=${ASSUME_YES}"

  if ask_yes "1/7 Symlink config files?" y; then
    step_links
  else
    skip "symlinks"
  fi

  if ask_yes "2/7 Install apt packages (tmux peco gh git gpg)?" y; then
    step_packages
  else
    skip "apt packages"
  fi

  if ask_yes "3/7 Install ghq and prepare /src?" y; then
    step_ghq
  else
    skip "ghq"
  fi

  if ask_yes "4/7 Install tmux plugins (tpm + tmux-sensible)?" y; then
    step_tpm
  else
    skip "tpm"
  fi

  if ask_yes "5/7 Install win32yank.exe for WSL clipboard?" y; then
    step_win32yank
  else
    skip "win32yank"
  fi

  if ask_yes "6/7 Install powerline-shell?" y; then
    step_powerline
  else
    skip "powerline-shell"
  fi

  if ask_yes "7/7 Copy Cursor user rules to ~/.cursor/rules?" y; then
    step_cursor_rules
  else
    skip "cursor rules"
  fi

  print_cursor_plugins
  print_secrets_note
  ok "setup finished"
}

main
