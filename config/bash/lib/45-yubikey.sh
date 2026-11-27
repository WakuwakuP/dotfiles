# Windows owns the USB device. WSL's OpenSSH delegates FIDO operations to it.
if [[ -z ${SSH_SK_HELPER:-} && -n ${WSL_DISTRO_NAME:-} ]]; then
  for _yk_helper in "$(command -v ssh-sk-helper.exe || true)" \
    '/mnt/c/Windows/System32/OpenSSH/ssh-sk-helper.exe' \
    '/mnt/c/Program Files/OpenSSH/ssh-sk-helper.exe'; do
    if [[ -f "$_yk_helper" && -x "$_yk_helper" ]]; then
      export SSH_SK_HELPER="$_yk_helper"
      break
    fi
  done
  unset _yk_helper
fi
