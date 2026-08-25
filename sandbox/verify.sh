#!/usr/bin/env bash
# Run inside the sandbox after setup.sh --yes.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/bin:${PATH}"

fail=0
pass() { printf 'OK   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

check() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    bad "$name"
  fi
}

echo "== setup =="
./setup.sh --yes

echo
echo "== verify =="

is_link_to() {
  local dest="$1"
  local suffix="$2"
  [[ -L "$dest" ]] || return 1
  local target
  target="$(readlink -f "$dest")"
  [[ "$target" == *"$suffix" ]]
}

check "bashrc linked" is_link_to "$HOME/.bashrc" "/config/bash/bashrc"
check "profile linked" is_link_to "$HOME/.profile" "/config/bash/profile"
check "gitconfig linked" is_link_to "$HOME/.gitconfig" "/config/git/gitconfig"
check "tmux.conf linked" is_link_to "$HOME/.tmux.conf" "/config/tmux/tmux.conf"
check "nanorc linked" is_link_to "$HOME/.nanorc" "/config/nano/nanorc"
check "peco linked" is_link_to "$HOME/.peco" "/config/peco"
check "gh config linked" is_link_to "$HOME/.config/gh/config.yml" "/config/gh/config.yml"
check "cursor rule linked" is_link_to "$HOME/.cursor/rules/respond-in-japanese.mdc" "/cursor/rules/respond-in-japanese.mdc"

check "tmux installed" command -v tmux
check "peco installed" command -v peco
check "gh installed" command -v gh
check "ghq installed" command -v ghq
check "powerline-shell installed" command -v powerline-shell
check "ghq root /src exists" test -d /src
check "tpm cloned" test -d "$HOME/.tmux/plugins/tpm/.git"
check "tmux-sensible cloned" test -d "$HOME/.tmux/plugins/tmux-sensible"

check "git user.name" test "$(git config --global user.name)" = WakuwakuP
check "git user.email" test "$(git config --global user.email)" = naoki.fujisawa@wakuwakup.net
check "git gpgsign" test "$(git config --global commit.gpgsign)" = true
check "ghq.root" test "$(git config --global ghq.root)" = /src

# Interactive bash without auto-creating a tmux session.
eval_in_bash() {
  SSH_CONNECTION="sandbox 0 0 0" bash -ic "$1"
}

check "peco-ghql defined" eval_in_bash "type peco-ghql >/dev/null"
check "peco-history defined" eval_in_bash "type peco-history >/dev/null"
check "alias ll defined" eval_in_bash "alias ll >/dev/null"
check "DOTFILES exported" eval_in_bash "[[ -n \"\$DOTFILES\" && -d \"\$DOTFILES/config/bash/lib\" ]]"

if eval_in_bash '[[ "$(type -t ssh)" == alias ]]'; then
  bad "ssh is aliased outside tmux (should only wrap inside tmux)"
else
  pass "ssh is not aliased outside tmux"
fi

if command -v win32yank.exe >/dev/null 2>&1; then
  bad "win32yank.exe should be skipped on non-WSL Linux"
else
  pass "win32yank.exe skipped on Linux sandbox"
fi

if tmux -f "$HOME/.tmux.conf" start-server \
  && tmux -f "$HOME/.tmux.conf" new-session -d -s dotfiles-verify \
  && tmux -f "$HOME/.tmux.conf" show -gv prefix | grep -qx C-t; then
  pass "tmux prefix is C-t"
else
  bad "tmux prefix is C-t"
fi
tmux -f "$HOME/.tmux.conf" kill-session -t dotfiles-verify >/dev/null 2>&1 || true
tmux kill-server >/dev/null 2>&1 || true

echo
if [[ "$fail" -eq 0 ]]; then
  echo "sandbox verify: all checks passed"
  exit 0
fi
echo "sandbox verify: $fail check(s) failed"
exit 1
