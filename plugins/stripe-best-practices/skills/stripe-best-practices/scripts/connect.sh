#!/usr/bin/env bash
# Connect this agent to "stripe-best-practices" on Orbivo. One connection covers every skill in the pack.
# Blocks internally while the user finishes the browser step. Do NOT poll from
# the calling agent — this script handles polling.
set -eu

BASE="${ORBIVO_ORIGIN:-https://orbivo.co}"
DIR="${ORBIVO_DIR:-$HOME/.orbivo}"
PRODUCT="${ORBIVO_PRODUCT:-stripe-best-practices}"
LABEL="${ORBIVO_LABEL:-$(hostname 2>/dev/null || echo agent)}"
LABEL=$(printf '%s' "$LABEL" | tr -cd 'A-Za-z0-9 ._-' | cut -c1-60)
TOKEN_FILE="$DIR/use-$PRODUCT.token"

START=$(curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"intent\":\"use\",\"productSlug\":\"$PRODUCT\",\"label\":\"$LABEL\"}" \
  "$BASE/api/v1/connect/start")

DEVICE_CODE=$(printf '%s' "$START" | sed -n 's/.*"deviceCode":"\([^"]*\)".*/\1/p')
VERIFY_URL=$(printf '%s' "$START" | sed -n 's/.*"verificationUrl":"\([^"]*\)".*/\1/p')
INTERVAL=$(printf '%s' "$START" | sed -n 's/.*"interval":\([0-9]*\).*/\1/p')
[ -z "$INTERVAL" ] && INTERVAL=5

if [ -z "$DEVICE_CODE" ] || [ -z "$VERIFY_URL" ]; then
  echo "ACTION REQUIRED — Orbivo did not return a connection link." >&2
  printf '%s\n' "$START" >&2
  exit 1
fi

echo "ACTION REQUIRED — this is not an error. Do not poll the server yourself."
echo "Tell your user (in their current conversation language) to open this page:"
echo "  $VERIFY_URL"
echo "Explain in friendly natural language that the page will guide them through"
echo "signing in, purchasing if needed, and finishing the connection for this agent."
echo "Do not mention tokens or scripts or file paths to the user."
echo "Waiting (this script blocks; up to 10 minutes)..."

if command -v open >/dev/null 2>&1; then open "$VERIFY_URL" >/dev/null 2>&1 || true
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$VERIFY_URL" >/dev/null 2>&1 || true
fi

i=0
while [ "$i" -lt 120 ]; do
  sleep "$INTERVAL"
  RESP=$(curl -sS -X POST -H "Content-Type: application/json" \
    -d "{\"deviceCode\":\"$DEVICE_CODE\"}" "$BASE/api/v1/connect/poll" || true)
  STATUS=$(printf '%s' "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
  if [ "$STATUS" = "approved" ]; then
    TOKEN=$(printf '%s' "$RESP" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    if [ -z "$TOKEN" ]; then
      echo "Server reported approved but returned no credential. Run this script again." >&2
      exit 1
    fi
    mkdir -p "$DIR"
    umask 077
    printf '%s' "$TOKEN" > "$TOKEN_FILE"
    echo "OK Connected. You can continue your task."
    exit 0
  fi
  if [ "$STATUS" = "expired" ]; then
    echo "Connection window expired. Run this script again." >&2
    exit 1
  fi
  i=$((i + 1))
done

echo "Timed out after 10 minutes. Run this script again." >&2
exit 2
