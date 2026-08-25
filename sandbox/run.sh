#!/usr/bin/env bash
# Build and run the Linux sandbox. Uses Docker Desktop on Windows when
# the WSL docker.sock is missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
IMAGE="${IMAGE:-waku-dotfiles-sandbox}"
MODE="${1:-verify}"

usage() {
  cat <<'EOF'
Usage: ./sandbox/run.sh [verify|shell|build]

  verify  Build, run setup.sh --yes, then assert the restored environment
  shell   Interactive bash after the same setup (tmux auto-attach is active)
  build   Build the image only
EOF
}

pick_docker() {
  cd "$ROOT"
  VOLUME_SRC="$ROOT"
  USE_VOLUME=1

  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
    return 0
  fi

  local exe
  if command -v docker.exe >/dev/null 2>&1; then
    exe="$(command -v docker.exe)"
  elif [[ -x /mnt/c/Program\ Files/Docker/Docker/resources/bin/docker.exe ]]; then
    exe="/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"
  else
    echo "Docker is not available. Start Docker Desktop, or expose /var/run/docker.sock." >&2
    exit 1
  fi

  if ! "$exe" info >/dev/null 2>&1; then
    echo "docker.exe cannot reach Docker Desktop." >&2
    exit 1
  fi

  DOCKER=("$exe")
  # Docker Desktop in this WSL distro cannot bind-mount the Linux filesystem
  # (distro-services socket is missing). The image COPY is the source of truth.
  USE_VOLUME=0
}

tty_args() {
  if [[ -t 0 && -t 1 ]]; then
    echo -it
  else
    echo -i
  fi
}

build_image() {
  "${DOCKER[@]}" build -t "$IMAGE" -f sandbox/Dockerfile .
}

run_container() {
  local args=(--rm)
  # shellcheck disable=SC2206
  args+=($(tty_args))
  if [[ "${USE_VOLUME}" == 1 ]]; then
    args+=(-v "${VOLUME_SRC}:/home/waku/dotfiles")
  fi
  args+=(-e "TERM=${TERM:-xterm-256color}" -w /home/waku/dotfiles "$IMAGE")
  "${DOCKER[@]}" run "${args[@]}" "$@"
}

case "$MODE" in
  -h|--help) usage; exit 0 ;;
  verify|shell|build) ;;
  *) usage; exit 1 ;;
esac

pick_docker
echo "docker: ${DOCKER[*]}"
echo "volume: $VOLUME_SRC"

if [[ "$MODE" == build ]]; then
  build_image
  exit 0
fi

build_image

if [[ "$MODE" == shell ]]; then
  run_container bash -lc './setup.sh --yes; exec bash -l'
else
  run_container ./sandbox/verify.sh
fi
