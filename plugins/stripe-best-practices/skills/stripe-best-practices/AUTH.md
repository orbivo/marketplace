# Orbivo Access

This skill streams its real files from Orbivo. A 401, 402, or 403 response is an
expected identity, purchase, or access step — never a task failure. One connection
covers every skill in this pack.

## How the connection works

The bundled scripts manage the user's connection for you:

- `scripts/connect.sh` (macOS/Linux) and `scripts/connect.ps1` (Windows) start the
  user's authorization flow. They print a single browser link, then **block** until the
  user finishes signing in, purchasing if needed, and approving this agent. Do not poll
  the server yourself.
- `scripts/run.sh` (and `run.ps1`) fetches a file. If the user has not connected yet —
  or the previous connection was revoked — it automatically invokes `connect.sh` for
  you and retries once. You will not normally see 401 / 402 / 403 directly.

## If a fetch returns "ACTION REQUIRED"

1. Run `bash scripts/connect.sh` (Windows: `powershell -ExecutionPolicy Bypass -File scripts/connect.ps1`).
   It will print a URL and block — do not call it again, do not poll the server.
2. While it blocks, tell your user — in their current conversation language — to open
   the printed URL in their browser. Explain that the page will guide them through
   signing in, completing any purchase, and finishing the connection for this agent.
   Use friendly natural language. Do not mention tokens, scripts, or file paths.
3. When `connect.sh` exits with `OK Connected`, retry the original request with
   `scripts/run.sh` — it will succeed.

If `connect.sh` exits with an "expired" or "timed out" message, just run it again.

## If your user has a passphrase for a private pack

Some private packs accept a shared passphrase as an alternative to signing in.

1. Ask your user for the passphrase. Do not guess it.
2. Set it for one fetch and retry:

```
ORBIVO_PASSWORD='<the passphrase>' bash scripts/run.sh SKILL.md
```

Never log the passphrase. Treat it like a one-shot credential the user shared with you.

## Useful endpoints (informational)

- Public file list: https://orbivo.co/api/v1/s/stripe-best-practices
- Product page (for the user, not for you to fetch): https://orbivo.co/p/stripe-best-practices
