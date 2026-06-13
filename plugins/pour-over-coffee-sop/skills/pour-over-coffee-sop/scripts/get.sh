#!/usr/bin/env bash
# Fetch a streamed file of "pour-over-coffee-sop" from Orbivo.
# Usage: scripts/get.sh <path>
# Examples:
#   scripts/get.sh SKILL.md
#   scripts/get.sh references/guide.md
#   scripts/get.sh references/aws/iam.md  (nested folders work too)
#
# Identity sources, checked in order:
#   - Authorization Bearer token from $ORBIVO_TOKEN_FILE (default ~/.orbivo/token)
#   - X-Orbivo-Password header from env $ORBIVO_PASSWORD (private skills with a passphrase)
#
# A 401/402/403 response is an expected identity/paywall/gate step, not an error —
# read AUTH.md and the printed instructions, complete them, then retry.
set -euo pipefail

PATH_ARG="${1:?usage: get.sh <path>}"
TOKEN_FILE="${ORBIVO_TOKEN_FILE:-$HOME/.orbivo/token}"

ARGS=()
if [ -f "$TOKEN_FILE" ]; then
  ARGS+=(-H "Authorization: Bearer $(cat "$TOKEN_FILE")")
fi
if [ -n "${ORBIVO_PASSWORD:-}" ]; then
  ARGS+=(-H "X-Orbivo-Password: $ORBIVO_PASSWORD")
fi

# No -f on purpose: 4xx bodies contain the instructions the agent must read.
# ${ARGS[@]+...} keeps bash 3.2 (macOS default) happy under set -u with an empty array.
curl -sSL ${ARGS[@]+"${ARGS[@]}"} "https://orbivo.co/api/v1/s/pour-over-coffee-sop/$PATH_ARG"
