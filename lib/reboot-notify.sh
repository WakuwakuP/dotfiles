# shellcheck shell=bash

reboot_notify_cron_ready() {
  if [[ -d /run/systemd/system ]]; then
    sudo systemctl enable --now cron && systemctl is-active --quiet cron
  else
    sudo service cron start && sudo service cron status >/dev/null
  fi
}

step_reboot_notify() (
  # Keep secret input out of tracing, and contain umask/traps in this subshell.
  set +x
  umask 077
  if [[ "${ASSUME_YES:-0}" == 1 ]]; then
    skip "reboot notifications in non-interactive mode"
    return 0
  fi

  local dependency missing=0
  for dependency in curl jq crontab; do
    command -v "$dependency" >/dev/null 2>&1 || missing=1
  done
  [[ -r /etc/ssl/certs/ca-certificates.crt ]] || missing=1
  if [[ "$missing" == 1 ]]; then
    sudo apt-get update || return 1
    sudo apt-get install -y curl jq cron ca-certificates || return 1
  fi

  local config_dir config_file script webhook_url='' existing='' quoted_script quoted_config
  config_dir=$(realpath -m -- "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles") || return 1
  config_file="$config_dir/reboot-notify.json"
  script="${DOTFILES}/scripts/check-reboot.sh"
  case "$config_dir/" in
    "$DOTFILES/"*) fail "notification secrets must be stored outside the repository"; return 1 ;;
  esac
  # Newlines and percent signs have special meanings in crontab, even in quotes.
  if [[ "$script$config_file" == *$'\n'* || "$script$config_file" == *%* ]]; then
    fail "notification paths cannot contain newlines or percent signs"
    return 1
  fi
  if [[ -L "$config_file" || ( -e "$config_file" && ! -f "$config_file" ) ]]; then
    fail "notification config must be a regular file, not a symlink"
    return 1
  fi
  if [[ -f "$config_file" ]]; then
    existing=$(jq -er '.webhook_url | select(type == "string")' "$config_file" 2>/dev/null) || existing=''
    [[ "$existing" =~ ^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_.-]+$ ]] || existing=''
  fi

  info "Notify Discord of hostname and packages every day at 12:00 until reboot; no test message will be sent"
  if [[ -n "$existing" ]]; then
    printf 'Discord Webhook URL (hidden; empty keeps existing): ' >&2
  else
    printf 'Discord Webhook URL (hidden; empty skips): ' >&2
  fi
  if ! IFS= read -rs webhook_url; then
    printf '\n' >&2
    fail "could not read Webhook URL"
    return 1
  fi
  printf '\n' >&2
  webhook_url="${webhook_url:-$existing}"
  if [[ -z "$webhook_url" ]]; then
    skip "reboot notifications (no Webhook URL)"
    return 0
  fi
  if [[ ! "$webhook_url" =~ ^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_.-]+$ ]]; then
    fail "invalid Discord Webhook URL"
    return 1
  fi

  local temp_dir config_temp='' cron_status
  temp_dir=$(mktemp -d) || return 1
  trap 'rm -rf -- "$temp_dir"; if [[ -n "$config_temp" ]]; then rm -f -- "$config_temp"; fi' EXIT
  if LC_ALL=C crontab -l > "$temp_dir/current" 2> "$temp_dir/error"; then
    :
  else
    cron_status=$?
    if [[ "$cron_status" == 1 ]] && grep -q '^no crontab for ' "$temp_dir/error"; then
      : > "$temp_dir/current"
    else
      fail "could not read existing crontab; nothing was overwritten"
      return 1
    fi
  fi

  quoted_script=$(jq -rn --arg path "$script" '$path | @sh') || return 1
  quoted_config=$(jq -rn --arg path "$config_file" '$path | @sh') || return 1
  # Replace only our tagged job; preserve all unrelated jobs and environment lines.
  sed '/ # dotfiles-reboot-notify$/d' "$temp_dir/current" > "$temp_dir/new" || return 1
  printf '0 12 * * * PATH=/usr/local/bin:/usr/bin:/bin /bin/bash %s --config %s # dotfiles-reboot-notify\n' \
    "$quoted_script" "$quoted_config" >> "$temp_dir/new"

  if ! reboot_notify_cron_ready; then
    fail "cron is not running; notification job was not registered (on WSL, enable systemd or start cron)"
    return 1
  fi
  mkdir -p "$config_dir" || return 1
  config_temp=$(mktemp "$config_dir/.reboot-notify.XXXXXX") || return 1
  # Pass the secret through stdin instead of exposing it in process arguments.
  if ! printf '%s' "$webhook_url" | jq -Rs '{webhook_url: .}' > "$config_temp"; then
    return 1
  fi
  chmod 600 "$config_temp" && mv -f -- "$config_temp" "$config_file" || return 1
  config_temp=''
  if ! crontab "$temp_dir/new"; then
    fail "notification config saved, but crontab registration failed"
    return 1
  fi
  ok "reboot notification configured: daily at 12:00 (system timezone), cron is running"
)
