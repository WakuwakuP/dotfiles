#!/usr/bin/env bash
# Offline setup checks. Never modify real services, packages, or crontabs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/setup.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT
export HOME="$TEMP_DIR/home"
export XDG_CONFIG_HOME="$HOME/config with 'quotes'"
mkdir -p "$HOME"
CONFIG="$XDG_CONFIG_HOME/dotfiles/reboot-notify.json"
CRON="$TEMP_DIR/crontab"
LOG="$TEMP_DIR/log"
WEBHOOK='https://discord.com/api/webhooks/123/test-token'

sudo() { printf 'sudo %s\n' "$*" >> "$LOG"; }
reboot_notify_cron_ready() {
  echo cron-ready >> "$LOG"
  return "${CRON_READY_STATUS:-0}"
}
crontab() {
  if [[ "$1" == -l ]]; then
    if [[ "${CRON_READ_ERROR:-0}" == 1 ]]; then
      echo 'permission denied' >&2
      return 1
    elif [[ -f "$CRON" ]]; then
      cat "$CRON"
    else
      echo 'no crontab for testuser' >&2
      return 1
    fi
  else
    cp "$1" "$CRON"
    echo cron-installed >> "$LOG"
  fi
}
run_setup() {
  printf '%s\n' "$1" | step_reboot_notify > "$TEMP_DIR/stdout" 2> "$TEMP_DIR/stderr"
}

run_setup ''
[[ ! -e "$CONFIG" && ! -e "$CRON" ]]
echo 'OK   Empty input without saved URL skips configuration'

run_setup "$WEBHOOK"
[[ $(stat -c %a "$CONFIG") == 600 ]]
jq -e --arg url "$WEBHOOK" '.webhook_url == $url' "$CONFIG" >/dev/null
[[ $(grep -c ' # dotfiles-reboot-notify$' "$CRON") == 1 ]]
grep -q '^0 12 \* \* \* ' "$CRON"
grep -q cron-ready "$LOG"
! grep -Fq "$WEBHOOK" "$CRON" "$TEMP_DIR/stdout" "$TEMP_DIR/stderr" "$LOG"
# Parse the generated cron command using /bin/sh; verify quoted paths round-trip.
cron_command=$(sed 's/^0 12 \* \* \* //' "$CRON")
printf '%s\n' "${cron_command/\/bin\/bash/printf '%s\\n'}" > "$TEMP_DIR/parse-command.sh"
/bin/sh "$TEMP_DIR/parse-command.sh" > "$TEMP_DIR/parsed"
grep -Fxq "$CONFIG" "$TEMP_DIR/parsed"
echo 'OK   Secure config, service check, daily job, and quoted paths'

printf 'MAILTO=test@example.com\n5 1 * * * echo keep-me\n' >> "$CRON"
run_setup ''
[[ $(grep -c ' # dotfiles-reboot-notify$' "$CRON") == 1 ]]
grep -Fxq '5 1 * * * echo keep-me' "$CRON"
grep -Fxq 'MAILTO=test@example.com' "$CRON"
jq -e --arg url "$WEBHOOK" '.webhook_url == $url' "$CONFIG" >/dev/null
echo 'OK   Rerun reuses URL and preserves unrelated cron entries'

cp "$CONFIG" "$TEMP_DIR/config-before"
cp "$CRON" "$TEMP_DIR/cron-before"
if run_setup 'https://example.com/secret'; then exit 1; fi
cmp "$CONFIG" "$TEMP_DIR/config-before"
cmp "$CRON" "$TEMP_DIR/cron-before"
! grep -q secret "$TEMP_DIR/stderr"
echo 'OK   Invalid URL leaves existing state unchanged'

if CRON_READ_ERROR=1 run_setup "$WEBHOOK"; then exit 1; fi
cmp "$CRON" "$TEMP_DIR/cron-before"
echo 'OK   Crontab read failures never overwrite jobs'

if CRON_READY_STATUS=1 run_setup "$WEBHOOK"; then exit 1; fi
cmp "$CRON" "$TEMP_DIR/cron-before"
echo 'OK   Inactive cron reports failure without registering a job'

(
  step_links() { :; }; step_packages() { :; }; step_ghq() { :; }
  step_tpm() { :; }; step_win32yank() { :; }; step_starship() { :; }
  step_cursor_rules() { :; }; print_cursor_plugins() { :; }; print_secrets_note() { :; }
  printf 'n\nn\nn\nn\nn\nn\nn\nn\ny\n\n' | main
) > "$TEMP_DIR/stdout" 2> "$TEMP_DIR/stderr"
[[ $(grep -c ' # dotfiles-reboot-notify$' "$CRON") == 1 ]]
echo 'OK   Interactive setup reaches notification configuration as step nine'

(
  ASSUME_YES=1
  step_reboot_notify </dev/null
  step_links() { :; }; step_packages() { :; }; step_ghq() { :; }
  step_tpm() { :; }; step_win32yank() { :; }; step_starship() { :; }
  step_cursor_rules() { :; }; print_cursor_plugins() { :; }; print_secrets_note() { :; }
  step_reboot_notify() { echo 'FAIL unexpected notification setup' >&2; return 1; }
  main </dev/null
) > "$TEMP_DIR/stdout"
cmp "$CRON" "$TEMP_DIR/cron-before"
echo 'OK   Non-interactive setup never prompts or configures notifications'

(
  command() {
    if [[ "$*" == '-v curl' ]]; then return 1; fi
    builtin command "$@"
  }
  run_setup ''
)
grep -Fq 'sudo apt-get install -y curl jq cron ca-certificates' "$LOG"
echo 'OK   Missing dependencies are installed through apt'

(
  export XDG_CONFIG_HOME="$DOTFILES/.test-config"
  if run_setup "$WEBHOOK"; then exit 1; fi
)
[[ ! -e "$DOTFILES/.test-config" ]]
echo 'OK   Secrets cannot be stored inside the repository'

mv "$CONFIG" "$TEMP_DIR/linked-config"
ln -s "$TEMP_DIR/linked-config" "$CONFIG"
if run_setup "$WEBHOOK"; then exit 1; fi
cmp "$TEMP_DIR/linked-config" "$TEMP_DIR/config-before"
echo 'OK   Symlink config is rejected without modifying its target'

# The initial installer redirects piped setup input to /dev/tty already.
bash -n "$ROOT/install.sh" "$ROOT/setup.sh" "$ROOT/lib/reboot-notify.sh"
echo 'OK   Bootstrap and setup syntax'
