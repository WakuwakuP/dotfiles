#!/bin/sh
# Invoked on a Linux server only by the explicit host --install command.
set -eu
umask 077
file=$HOME/.ssh/authorized_keys
mkdir -p "$HOME/.ssh"
exec 9>>"$file"
flock -x 9
while [ "$#" -ge 2 ]; do
  role=$1
  blob=$2
  shift 2
  # Keep existing options on a restricted key; never add a second unrestricted entry.
  if awk -v blob="$blob" '
    !/^[[:space:]]*#/ {
      for (i=2; i<=NF; i++) if ($(i-1) == "sk-ssh-ed25519@openssh.com" && $i == blob) found=1
    }
    END {exit !found}
  ' "$file"; then
    printf 'Already registered: %s\n' "$role"
  else
    printf '\nsk-ssh-ed25519@openssh.com %s yubikey-%s\n' "$blob" "$role" >&9
    printf 'Registered: %s\n' "$role"
  fi
done
