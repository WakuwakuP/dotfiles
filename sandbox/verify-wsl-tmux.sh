#!/usr/bin/env bash
# Check which server the login shell creates, lists and attaches to.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export PATH="$tmp:$PATH" TMUX_TEST_LOG="$tmp/calls"
unset TMUX STY NO_TMUX SSH_CONNECTION SSH_CONECTION TERM_PROGRAM ZED_TERM VSCODE_INJECTION

cat > "$tmp/whoami.exe" <<'EOF'
#!/bin/sh
printf '"Mandatory Label","Label","%s",""\n' "$TEST_SID"
EOF
cat > "$tmp/tmux" <<'EOF'
#!/bin/sh
echo "$*" >> "$TMUX_TEST_LOG"
if [ "$1" = -L ]; then shift 2; fi
case "$1" in
  list-sessions)
    test "$TEST_SESSION" != empty || exit 1
    if [ "$#" = 3 ]; then echo "$TEST_SESSION"; else echo '0: 1 windows'; fi ;;
esac
EOF
chmod +x "$tmp/whoami.exe" "$tmp/tmux"

run_login() {
  : > "$TMUX_TEST_LOG"
  bash --noprofile --norc -lc '
    PS1=test
    source "$1/config/bash/lib/00-helpers.sh"
    source "$1/config/bash/lib/60-tmux.sh"
  ' _ "$root" <<< "${1:-}" >/dev/null
}

export WSL_DISTRO_NAME=Ubuntu TEST_SID=S-1-16-12288 TEST_SESSION=empty
run_login
grep -Fxq -- '-L wsl-admin list-sessions -F #{session_attached}' "$TMUX_TEST_LOG"
grep -Fxq -- '-L wsl-admin new-session' "$TMUX_TEST_LOG"
export TEST_SESSION=0
run_login
grep -Fxq -- '-L wsl-admin list-sessions' "$TMUX_TEST_LOG"
grep -Fxq -- '-L wsl-admin attach-session' "$TMUX_TEST_LOG"
run_login 0
grep -Fxq -- '-L wsl-admin attach -t 0' "$TMUX_TEST_LOG"
TEST_SESSION=1 run_login
grep -Fxq -- '-L wsl-admin new-session' "$TMUX_TEST_LOG"

export TEST_SID=S-1-16-8192
run_login
grep -Fxq 'attach-session' "$TMUX_TEST_LOG"
unset WSL_DISTRO_NAME
export TEST_SID=S-1-16-12288
run_login
grep -Fxq 'attach-session' "$TMUX_TEST_LOG"
echo 'OK   tmux server selection for elevated WSL, ordinary WSL and Linux'
