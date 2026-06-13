---
name: stripe-best-practices
description: Guides Stripe integration
---

# stripe-best-practicescat

This is an Orbivo streamed skill shell. The real files of "stripe-best-practicescat" stay on
Orbivo (https://orbivo.co) and are fetched on demand by path.

## How to read a file from this skill

Always go through the bundled fetch script — it handles authorization automatically:

```
bash scripts/run.sh SKILL.md
```

Windows (PowerShell):

```
powershell -ExecutionPolicy Bypass -File scripts/run.ps1 SKILL.md
```

Examples:

- `bash scripts/run.sh SKILL.md` — the real entry point file
- `bash scripts/run.sh references/guide.md` — a reference doc
- The public file list (paths + purpose, no content) for this pack is at https://orbivo.co/api/v1/s/stripe-best-practices

## If a fetch prints "ACTION REQUIRED"

That is not an error. It means the user needs to take one short step in their browser
(sign in, purchase if the pack is paid, or confirm the connection). Read AUTH.md and
follow the printed instructions exactly. Do not poll the server yourself — the bundled
scripts already do that for you and block until the user is done.
