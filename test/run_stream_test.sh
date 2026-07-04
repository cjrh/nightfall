#!/usr/bin/env bash
# Launch a Sunshine stream and test decode.
# Uses existing paired cert from Godot config.
set -uo pipefail

CONFIG="$HOME/.local/share/godot/app_userdata/Nightfall/addons/nightfall-stream/config.ini"
SERVER="${1:-127.0.0.1}"
APP_ID="${2:-881448767}"  # Desktop app

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$CONFIG" ] || die "Config not found at $CONFIG"

# Extract client cert and key
CERT_TMP=$(mktemp)
KEY_TMP=$(mktemp)
trap "rm -f $CERT_TMP $KEY_TMP" EXIT

awk '/^certificate=/{p=1} p{print; if(/-----END CERTIFICATE-----/) exit}' "$CONFIG" | sed 's/^certificate=//;s/^"//;s/"$//' > "$CERT_TMP"
awk '/^key=/{p=1} p{print; if(/-----END RSA PRIVATE KEY-----/) exit}' "$CONFIG" | sed 's/^key=//;s/^"//;s/"$//' > "$KEY_TMP"
CLIENT_UID=$(grep '^uniqueid=' "$CONFIG" | sed 's/uniqueid=//;s/"//g')

# Get HTTPS port
HTTPS_PORT=$(sed -n 's/.*https_port=\([0-9]*\).*/\1/p' "$CONFIG" | head -1)
[ -n "$HTTPS_PORT" ] || HTTPS_PORT=47984

UUID="testcli$(date +%s)"
echo "=== Test Client ==="
echo "Server: $SERVER:$HTTPS_PORT"
echo "App ID: $APP_ID"
echo "UUID: $UUID"

CURL="curl -sk --cert $CERT_TMP --key $KEY_TMP"

# Check for existing session
echo "--- Server Info ---"
SERVERINFO=$(timeout 10 $CURL "https://${SERVER}:${HTTPS_PORT}/serverinfo?uniqueid=${CLIENT_UID}&uuid=${UUID}" 2>&1) || true
CURRENT_GAME=$(echo "$SERVERINFO" | sed -n 's/.*<currentgame>\([^<]*\)<.*/\1/p')
SCM=$(echo "$SERVERINFO" | sed -n 's/.*<ServerCodecModeSupport>\([^<]*\)<.*/\1/p')
APPVER=$(echo "$SERVERINFO" | sed -n 's/.*<appversion>\([^<]*\)<.*/\1/p')
echo "Current game: ${CURRENT_GAME:-0}"
echo "Server codec mode support: ${SCM:-0}"
echo "App version: ${APPVER:-unknown}"

if [ -n "$CURRENT_GAME" ] && [ "$CURRENT_GAME" != "0" ]; then
    echo "Existing game running (id=$CURRENT_GAME), cancelling..."
    timeout 10 $CURL "https://${SERVER}:${HTTPS_PORT}/cancel?uniqueid=${CLIENT_UID}&uuid=${UUID}" >/dev/null 2>&1 || true
    sleep 2
fi

# Launch fresh stream
echo "--- Launching ---"
RIKEY=$(xxd -l 16 -p /dev/urandom)
RIKEYID=$(( RANDOM * RANDOM ))

LAUNCH_URL="https://${SERVER}:${HTTPS_PORT}/launch?uniqueid=${CLIENT_UID}&uuid=${UUID}&appid=${APP_ID}&rikey=${RIKEY}&rikeyid=${RIKEYID}&mode=1920x1080x60&surroundAudioInfo=0xCA0203&localAudioPlayMode=1"

RESPONSE=$(timeout 15 $CURL "$LAUNCH_URL" 2>&1) || die "Launch request failed or timed out"
echo "Response: ${RESPONSE:0:200}"

SESSION_URL=$(echo "$RESPONSE" | sed -n 's/.*<sessionUrl0>\([^<]*\)<.*/\1/p')
[ -n "$SESSION_URL" ] || die "Could not extract sessionUrl0 from response"
echo "Session URL: $SESSION_URL"

# Run the stream test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_BIN="${SCRIPT_DIR}/../addons/nightfall-stream/build/linux/stream_test"
[ -f "$TEST_BIN" ] || die "stream_test binary not found at $TEST_BIN"

echo "=== Running stream test ==="
"$TEST_BIN" "$SERVER" "$SESSION_URL" "${SCM:-0}" "${APPVER:-7.1.431.-1}"
EXIT_CODE=$?

# Cancel on exit
echo "--- Cancelling ---"
timeout 10 $CURL "https://${SERVER}:${HTTPS_PORT}/cancel?uniqueid=${CLIENT_UID}&uuid=${UUID}" >/dev/null 2>&1 || true
echo "Done (exit=$EXIT_CODE)"
exit $EXIT_CODE
