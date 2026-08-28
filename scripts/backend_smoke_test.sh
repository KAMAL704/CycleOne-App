#!/usr/bin/env bash
set -euo pipefail

# Read-only check for the public backend contract used by the Flutter app.
# Usage:
#   ./scripts/backend_smoke_test.sh
# or pass a different project explicitly:
#   SUPABASE_URL=https://... SUPABASE_ANON_KEY=ey... ./scripts/backend_smoke_test.sh

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_config="${script_dir}/../lib/core/config/app_config.dart"
if [[ -z "${SUPABASE_URL:-}" && -f "$app_config" ]]; then
  SUPABASE_URL="$(sed -n "s/.*defaultValue: '\(https:\/\/[^']*\)'.*/\1/p" "$app_config" | head -1)"
fi
if [[ -z "${SUPABASE_ANON_KEY:-}" && -f "$app_config" ]]; then
  SUPABASE_ANON_KEY="$(grep -o 'eyJ[A-Za-z0-9._-]*' "$app_config" | head -1)"
fi
: "${SUPABASE_URL:?Set SUPABASE_URL first}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY first}"

failures=0

request() {
  local path="$1"
  local body_file
  body_file="$(mktemp)"
  local code
  code="$(curl -sS -o "$body_file" -w '%{http_code}' \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    "${SUPABASE_URL%/}${path}")"
  if [[ "$code" != "200" ]]; then
    echo "FAIL ${path} (HTTP ${code})"
    sed -n '1,4p' "$body_file"
    rm -f "$body_file"
    failures=$((failures + 1))
    return 0
  fi
  rm -f "$body_file"
  echo "OK   ${path}"
}

request '/rest/v1/profiles?select=id,name,email,phone,registration_id,role,status,created_at,updated_at&limit=1'
request '/rest/v1/stands?select=id,name,location,latitude,longitude,capacity,status,esp_mac,esp_ssid,esp_password,esp_ip,esp_port&limit=1'
request '/rest/v1/cycles?select=id,cycle_number,qr_code,status,stand_id&limit=1'
request '/rest/v1/settings?select=key,value&limit=1'

# A missing RPC returns PGRST202. An existing RPC may return a normal auth or
# argument error because this smoke test intentionally does not send a session.
for function_name in start_cycle_ride end_cycle_ride; do
  body_file="$(mktemp)"
  if [[ "$function_name" == "start_cycle_ride" ]]; then
    payload='{"p_cycle_id":"00000000-0000-4000-8000-000000000001","p_start_stand_id":"00000000-0000-4000-8000-000000000002","p_esp_mac":"02:00:00:00:00:01"}'
  else
    payload='{"p_ride_id":"00000000-0000-4000-8000-000000000001","p_cycle_id":"00000000-0000-4000-8000-000000000002","p_end_stand_id":"00000000-0000-4000-8000-000000000003","p_esp_mac":"02:00:00:00:00:01"}'
  fi
  code="$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H 'content-type: application/json' \
    --data "$payload" "${SUPABASE_URL%/}/rest/v1/rpc/${function_name}")"
  if grep -q 'PGRST202' "$body_file"; then
    echo "FAIL /rest/v1/rpc/${function_name} (RPC is not deployed)"
    sed -n '1,4p' "$body_file"
    rm -f "$body_file"
    failures=$((failures + 1))
    continue
  fi
  echo "OK   /rest/v1/rpc/${function_name} (HTTP ${code}; auth/argument response is expected without a session)"
  rm -f "$body_file"
done

if (( failures > 0 )); then
  echo "Backend contract check failed (${failures} check(s))."
  exit 1
fi

echo 'Backend contract is present.'
