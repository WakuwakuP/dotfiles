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
echo "== configurable ghq root =="
printf '%s\ny\n' '~/custom ghq' | bash -c 'source ./setup.sh; step_ghq'
check "custom ghq.root" test "$(git config --global --includes --get ghq.root)" = "$HOME/custom ghq"
check "custom ghq root exists" test -d "$HOME/custom ghq"

bash -c 'source ./setup.sh; ASSUME_YES=1; step_ghq'
check "ghq.root preserved" test "$(git config --global --includes --get ghq.root)" = "$HOME/custom ghq"

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
check "gh config linked" is_link_to "$HOME/.config/gh/config.yml" "/config/gh/config.yml"
check "starship.toml linked" is_link_to "$HOME/.config/starship.toml" "/config/starship/starship.toml"
check "cursor rule linked" is_link_to "$HOME/.cursor/rules/respond-in-japanese.mdc" "/cursor/rules/respond-in-japanese.mdc"

check "tmux installed" command -v tmux
check "fzf installed" command -v fzf
has_bat() { command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; }
check "bat installed" has_bat
check "gh installed" command -v gh
check "ghq installed" command -v ghq
check "starship installed" command -v starship
check "ghq root exists" test -d "$(ghq root)"
check "tpm cloned" test -d "$HOME/.tmux/plugins/tpm/.git"
check "tmux-sensible cloned" test -d "$HOME/.tmux/plugins/tmux-sensible"

check "git user.name" test "$(git config --global user.name)" = WakuwakuP
check "git user.email" test "$(git config --global user.email)" = naoki.fujisawa@wakuwakup.net
check "git gpgsign" test "$(git config --global commit.gpgsign)" = true
check "ghq.root configured" test -n "$(git config --global --includes --get ghq.root)"

# Interactive bash without auto-creating a tmux session.
eval_in_bash() {
  SSH_CONNECTION="sandbox 0 0 0" bash -ic "$1"
}

check "g defined" eval_in_bash "type g >/dev/null"
check "fzf-ghql defined" eval_in_bash "type fzf-ghql >/dev/null"
check "fzf-history defined" eval_in_bash "type fzf-history >/dev/null"
check "FZF_DEFAULT_OPTS reverse" eval_in_bash '[[ "$FZF_DEFAULT_OPTS" == *--layout=reverse* ]]'
check "alias ll defined" eval_in_bash "alias ll >/dev/null"
check "DOTFILES exported" eval_in_bash "[[ -n \"\$DOTFILES\" && -d \"\$DOTFILES/config/bash/lib\" ]]"
check "starship initialized" eval_in_bash '[[ "$STARSHIP_SHELL" == bash ]]'

if eval_in_bash '[[ "$(type -t ssh)" == alias ]]'; then
  bad "ssh is aliased outside tmux (should only wrap inside tmux)"
else
  pass "ssh is not aliased outside tmux"
fi

eval_in_tmux_bash() {
  SSH_CONNECTION="sandbox 0 0 0" TMUX="dummy" bash -ic "$1"
}

if eval_in_tmux_bash '[[ "$(type -t ssh)" == alias ]]'; then
  pass "ssh is aliased inside tmux"
else
  bad "ssh should be aliased inside tmux"
fi

fzf_ssh_via_alias="$(
  SSH_CONNECTION="sandbox 0 0 0" TMUX="dummy" bash -ic '
    mkdir -p "$HOME/.ssh"
    printf "Host testhost\n" > "$HOME/.ssh/config"
    fzf() { echo testhost; }
    tmux_ssh() { printf "ALIAS:%s\n" "$1"; }
    alias ssh=tmux_ssh
    ssh() { printf "DIRECT:%s\n" "$1"; }
    fzf-ssh
  '
)"
if [[ "$fzf_ssh_via_alias" == *ALIAS:testhost* ]]; then
  pass "fzf-ssh uses ssh alias inside tmux"
else
  bad "fzf-ssh uses ssh alias inside tmux"
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
