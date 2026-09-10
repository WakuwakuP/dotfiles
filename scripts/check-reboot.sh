#!/usr/bin/env bash
# Notify Discord when Ubuntu reports that a reboot is required.

main() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/reboot-notify.json"
  local reboot_file="${REBOOT_FILE:-/var/run/reboot-required}"
  local packages_file="${PACKAGES_FILE:-/var/run/reboot-required.pkgs}"
  local dry_run=0 packages='' server_name payload webhook_url status dependency

  while (($#)); do
    case "$1" in
      --config)
        if (($# < 2)) || [[ -z "$2" ]]; then
          echo 'check-reboot: --config にはファイルパスが必要です' >&2
          return 1
        fi
        config="$2"
        shift 2
        ;;
      --dry-run) dry_run=1; shift ;;
      --help|-h)
        echo 'Usage: bash check-reboot.sh [--config FILE] [--dry-run]'
        return 0
        ;;
      *) echo 'check-reboot: 不明な引数です' >&2; return 1 ;;
    esac
  done

  [[ "$dry_run" == 1 || -f "$reboot_file" ]] || return 0
  for dependency in jq hostname; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      printf 'check-reboot: %s が必要です\n' "$dependency" >&2
      return 1
    fi
  done

  if [[ -e "$packages_file" ]]; then
    if ! packages=$(cat -- "$packages_file" 2>/dev/null); then
      echo 'check-reboot: パッケージ一覧を読み込めません' >&2
      return 1
    fi
  fi
  server_name=$(hostname) || return 1
  payload=$(jq -n --arg name "$server_name" --arg packages "$packages" '
    ($packages | split("\n") | map(select(length > 0)) | join(" ")) as $reason
    | ("システムの再起動が必要です。\n原因パッケージ: "
       + (if $reason == "" then "不明" else $reason end)) as $content
    | {
        username: $name[:80],
        content: ($content | if length > 2000 then .[:1999] + "…" else . end),
        allowed_mentions: {parse: []}
      }
  ') || return 1

  if [[ "$dry_run" == 1 ]]; then
    printf '%s\n' "$payload"
    return 0
  fi

  if ! webhook_url=$(jq -er '.webhook_url | select(type == "string")' "$config" 2>/dev/null) \
    || [[ ! "$webhook_url" =~ ^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_.-]+$ ]]; then
    echo 'check-reboot: 設定に有効な Discord Webhook URL が必要です' >&2
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo 'check-reboot: curl が必要です' >&2
    return 1
  fi

  # Keep the secret URL out of process arguments and error messages.
  # Disable .curlrc so user settings cannot enable tracing or redirects.
  if ! status=$(printf 'url = "%s"\n' "$webhook_url" | curl --disable --config - \
    --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    --header 'Content-Type: application/json' --data-binary "$payload" 2>/dev/null); then
    echo 'check-reboot: Discord への通信に失敗しました' >&2
    return 1
  fi
  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
    echo 'check-reboot: Discord への送信に失敗しました (HTTP エラー)' >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
