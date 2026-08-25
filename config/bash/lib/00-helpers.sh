# Shared predicates used by later modules.

is_exists() { type "$1" >/dev/null 2>&1; }
is_osx() { [[ $OSTYPE == darwin* ]]; }
is_screen_running() { [[ -n "${STY:-}" ]]; }
is_tmux_running() { [[ -n "${TMUX:-}" ]]; }
is_screen_or_tmux_running() { is_screen_running || is_tmux_running; }
shell_has_started_interactively() { [[ -n "${PS1:-}" ]]; }
is_ssh_running() { [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CONECTION:-}" ]]; }
is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" && -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; }
