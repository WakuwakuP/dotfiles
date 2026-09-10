#!/usr/bin/env bash
# Offline regression checks: curl is replaced so no requests can be sent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/check-reboot.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT
REBOOT_FILE="$TEMP_DIR/reboot-required"
PACKAGES_FILE="$TEMP_DIR/reboot-required.pkgs"
CONFIG="$TEMP_DIR/config.json"
CAPTURE="$TEMP_DIR/payload.json"
WEBHOOK='https://discord.com/api/webhooks/123/test-token'
printf '{"webhook_url":"%s"}\n' "$WEBHOOK" > "$CONFIG"

hostname() { printf 'test-host\n'; }
curl() {
  cat > "$TEMP_DIR/curl-config"
  while (($#)); do
    if [[ "$1" == --data-binary ]]; then
      printf '%s\n' "$2" > "$CAPTURE"
      shift
    fi
    shift
  done
  printf '%s' "${HTTP_STATUS:-204}"
  return "${CURL_EXIT:-0}"
}
run() { (main --config "$CONFIG" "$@") > "$TEMP_DIR/stdout" 2> "$TEMP_DIR/stderr"; }

run --config "$TEMP_DIR/missing"
[[ ! -e "$CAPTURE" && ! -s "$TEMP_DIR/stdout" ]]
echo 'OK   No reboot requires no config and sends nothing'

run --dry-run --config "$TEMP_DIR/missing"
jq -e '.content | contains("不明")' "$TEMP_DIR/stdout" >/dev/null
[[ ! -e "$CAPTURE" ]]
echo 'OK   Dry-run needs no marker or config and never sends'

touch "$REBOOT_FILE"
printf 'linux-image\nlibc"test\\pkg\n@everyone\n' > "$PACKAGES_FILE"
run
jq -e '.username == "test-host" and .allowed_mentions.parse == []
  and (.content | contains("libc\"test\\pkg"))' "$CAPTURE" >/dev/null
grep -Fq "$WEBHOOK" "$TEMP_DIR/curl-config"
echo 'OK   Hostname, JSON escaping, and disabled mentions'

rm "$PACKAGES_FILE"
run
jq -e '.content | contains("不明")' "$CAPTURE" >/dev/null
echo 'OK   Missing packages still notify'

printf '%03000d' 0 > "$PACKAGES_FILE"
run
jq -e '.content | length == 2000' "$CAPTURE" >/dev/null
echo 'OK   Message length is limited'

for config in '{' '[]' '{"webhook_url":"http://example.com/secret"}'; do
  printf '%s' "$config" > "$CONFIG"
  rm -f "$CAPTURE"
  if run; then echo 'FAIL invalid config accepted' >&2; exit 1; fi
  [[ ! -e "$CAPTURE" ]]
  ! grep -q secret "$TEMP_DIR/stderr"
done
echo 'OK   Invalid config never sends or leaks secrets'

printf '{"webhook_url":"%s"}\n' "$WEBHOOK" > "$CONFIG"
if HTTP_STATUS=429 run; then echo 'FAIL HTTP error ignored' >&2; exit 1; fi
if CURL_EXIT=28 run; then echo 'FAIL timeout ignored' >&2; exit 1; fi
! grep -Fq "$WEBHOOK" "$TEMP_DIR/stderr"
echo 'OK   HTTP and network failures return errors without leaking URL'
