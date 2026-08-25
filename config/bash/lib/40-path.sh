# PATH additions. Optional tools are loaded only when present.

if [[ -z ${TMUX:-} ]]; then
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif [ -x "${HOME}/.linuxbrew/bin/brew" ]; then
    eval "$("${HOME}/.linuxbrew/bin/brew" shellenv)"
  fi
fi

if [[ -d "${HOME}/.local/bin" ]]; then
  case ":$PATH:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:$PATH" ;;
  esac
fi

export GOPATH="${GOPATH:-$HOME/go}"
export GOBIN="${GOBIN:-$GOPATH/bin}"
export PATH="$PATH:$GOBIN"

if [ -s "${HOME}/.nvm/nvm.sh" ]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck source=/dev/null
  . "${NVM_DIR}/nvm.sh"
  [ -s "${NVM_DIR}/bash_completion" ] && . "${NVM_DIR}/bash_completion"
fi
