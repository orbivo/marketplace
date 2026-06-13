#!/usr/bin/env bash
# Fetch a streamed file of the "stripe-best-practices" skill (pack "stripe-best-practices") from Orbivo.
# Usage: bash scripts/run.sh <path>   e.g. bash scripts/run.sh SKILL.md
# Reads the pack credential from $HOME/.orbivo/use-stripe-best-practices.token. If missing,
# expired, or revoked, invokes scripts/connect.sh automatically (blocking) and retries once.
set -eu

PATH_ARG="${1:?usage: run.sh <path>}"
BASE="${ORBIVO_ORIGIN:-https://orbivo.co}"
DIR="${ORBIVO_DIR:-$HOME/.orbivo}"
PRODUCT="${ORBIVO_PRODUCT:-stripe-best-practices}"
SKILL="${ORBIVO_SKILL:-stripe-best-practices}"
TOKEN_FILE="$DIR/use-$PRODUCT.token"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ORBIVO_UA="orbivo-loader/1"
if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  ORBIVO_UA="claude-code orbivo-loader/1"
elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_SANDBOX_NETWORK_DISABLED:-}" ]; then
  ORBIVO_UA="codex orbivo-loader/1"
elif [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_AGENT:-}" ]; then
  ORBIVO_UA="cursor orbivo-loader/1"
fi

fetch_once() {
  if [ -f "$TOKEN_FILE" ]; then
    AUTH_HEADER="Authorization: Bearer $(cat "$TOKEN_FILE")"
  else
    AUTH_HEADER=""
  fi
  PW_HEADER=""
  if [ -n "${ORBIVO_PASSWORD:-}" ]; then
    PW_HEADER="X-Orbivo-Password: $ORBIVO_PASSWORD"
  fi
  URL="$BASE/api/v1/s/$PRODUCT/$SKILL/$PATH_ARG"
  if [ -n "$AUTH_HEADER" ] && [ -n "$PW_HEADER" ]; then
    RESP=$(curl -sS -A "$ORBIVO_UA" -w '\nHTTPSTATUS:%{http_code}' -H "$AUTH_HEADER" -H "$PW_HEADER" "$URL")
  elif [ -n "$AUTH_HEADER" ]; then
    RESP=$(curl -sS -A "$ORBIVO_UA" -w '\nHTTPSTATUS:%{http_code}' -H "$AUTH_HEADER" "$URL")
  elif [ -n "$PW_HEADER" ]; then
    RESP=$(curl -sS -A "$ORBIVO_UA" -w '\nHTTPSTATUS:%{http_code}' -H "$PW_HEADER" "$URL")
  else
    RESP=$(curl -sS -A "$ORBIVO_UA" -w '\nHTTPSTATUS:%{http_code}' "$URL")
  fi
  HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/.*HTTPSTATUS:\([0-9][0-9]*\)$/\1/p' | tail -n1)
  BODY=$(printf '%s' "$RESP" | sed 's/HTTPSTATUS:[0-9]*$//')
}

needs_connect() {
  case "$1" in 401|402|403) return 0 ;; *) return 1 ;; esac
}

fetch_once
if needs_connect "$HTTP_STATUS"; then
  rm -f "$TOKEN_FILE" 2>/dev/null || true
  ORBIVO_PRODUCT="$PRODUCT" bash "$SCRIPT_DIR/connect.sh" || CONNECT_EXIT=$?
  if [ "${CONNECT_EXIT:-0}" -ne 0 ]; then
    exit 1
  fi
  fetch_once
fi

printf '%s' "$BODY"
if [ "$HTTP_STATUS" -ge 400 ]; then
  exit 1
fi
exit 0
