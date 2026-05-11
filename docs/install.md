---
title: Install Peekaboo
summary: 'Install Peekaboo through Homebrew, npm/MCP, the Mac app, or a source checkout.'
description: Install the Peekaboo CLI, MCP server, or Mac app. Homebrew, npm, and source paths.
read_when:
  - 'setting up Peekaboo for the first time'
  - 'choosing between Homebrew, npm, Mac app, and source builds'
---

# Install

Peekaboo ships in three flavors. They all use the same Swift core and the same toolset — pick whichever surface fits your workflow.

## Homebrew (recommended)

The CLI is signed, notarized, and lives in [steipete/homebrew-tap](https://github.com/steipete/homebrew-tap).

```bash
brew install steipete/tap/peekaboo
peekaboo-mcp --version
```

Update with `brew upgrade steipete/tap/peekaboo`.

## npm (for MCP clients)

The npm package wraps the same CLI plus an MCP shim, so you can launch the server with `npx`:

```bash
npx -y @steipete/peekaboo-mcp mcp serve
```

This is the form you point Codex, Claude Code, and Cursor at. See [MCP.md](MCP.md).

## Mac app

The full menu-bar app (visualizer, permission flows, status item) is on the [Releases](https://github.com/openclaw/Peekaboo/releases/latest) page. The bundled CLI lives at `/Applications/Peekaboo.app/Contents/MacOS/peekaboo`; symlink it if you want it on your `PATH` without Homebrew.

## Build from source

Requires macOS 26.1+, Xcode 26+, Swift 6.2.

```bash
git clone --recurse-submodules https://github.com/openclaw/Peekaboo.git
cd Peekaboo
pnpm install
pnpm run build:cli         # debug build
pnpm run build:mcp:universal   # universal release
```

The output binary lives under `Apps/CLI/.build/...`. See [building.md](building.md) for signing, notarization, and the `pnpm run poltergeist:haunt` rapid-rebuild loop.

## Verify

```bash
peekaboo-mcp --version
peekaboo-mcp mcp serve
```

If any of those error out, jump to [permissions.md](permissions.md).


## MCP client registration

Codex:

```bash
codex mcp add peekaboo -- npx -y @steipete/peekaboo-mcp mcp serve
```

Claude Code:

```bash
claude mcp add peekaboo -- npx -y @steipete/peekaboo-mcp mcp serve
```

Sanity check:

```bash
peekaboo-mcp mcp serve
```
