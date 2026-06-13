---
name: pour-over-coffee-sop
description: Turn any agent into a pour-over brewing coach: exact dose and grind formulas, a timed pouring routine, and a one-variable-at-a-time flavor troubleshooting table — streamed on demand, always up to date.
---

# Pour-Over Coffee Brewing SOP

This is an Orbivo streamed skill shell: the real files are fetched by path from
https://orbivo.co/api/v1/s/pour-over-coffee-sop/<path> after reading the public manifest at
https://orbivo.co/api/v1/s/pour-over-coffee-sop; if a request returns 401 or 402, read AUTH.md,
complete the required user step, then retry the exact same path. You can use
`bash scripts/get.sh <path>` as a plain fetch fallback.
