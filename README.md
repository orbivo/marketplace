# Orbivo Skills Marketplace

Codex / Claude Code plugin marketplace bridge for [Orbivo](https://orbivo.co).

## Install

```bash
codex plugin marketplace add orbivo/marketplace
```

Then pick any plugin from the Orbivo catalog inside Codex.

## How it works

Each plugin in this repo is a **streamed shell** that fetches the real skill content from `https://orbivo.co/api/v1/s/<slug>/<path>` at run time. Authentication is per-user: a Bearer token from `~/.orbivo/token` (set up at https://orbivo.co/connect).

This repo is regenerated automatically by Orbivo when creators publish a new version.
