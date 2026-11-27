#!/bin/sh
# Invoked on a Linux server only by the explicit host --install command.
set -eu
umask 077
file=$HOME/.ssh/authorized_keys
mkdir -p "$HOME/.ssh"
exec 9>>"$file"
flock -x 9
# Keep options already stored on a registered key. If this file uses restrict,
# new keys get it too so they do not become a second unrestricted login.
restricted=0
if awk '
  !/^[[:space:]]*#/ && !/^[[:space:]]*$/ && $0 ~ /(^|[[:space:],])restrict([[:space:],]|$)/ { found = 1 }
  END { exit !found }
' "$file"; then
  restricted=1
fi
while [ "$#" -ge 2 ]; do
  role=$1
  blob=$2
  shift 2
  if awk -v blob="$blob" '
    !/^[[:space:]]*#/ {
      for (i=2; i<=NF; i++) if ($(i-1) == "sk-ssh-ed25519@openssh.com" && $i == blob) found=1
    }
    END {exit !found}
  ' "$file"; then
    printf 'Already registered: %s\n' "$role"
  else
    if [ "$restricted" -eq 1 ]; then
      printf '\nrestrict sk-ssh-ed25519@openssh.com %s yubikey-%s\n' "$blob" "$role" >&9
    else
      printf '\nsk-ssh-ed25519@openssh.com %s yubikey-%s\n' "$blob" "$role" >&9
    fi
    printf 'Registered: %s\n' "$role"
  fi
done
