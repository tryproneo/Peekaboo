---
title: MCP release checklist
summary: 'Static checklist for publishing MCP-only artifacts.'
---

# MCP release checklist

## 1) Build artifacts

- Build arm64 artifact: `pnpm run build:mcp:arm64`
- Optional universal artifact: `pnpm run build:mcp:universal`
- Confirm artifact names:
  - `peekaboo-mcp-macos-arm64.tar.gz`
  - `peekaboo-mcp-macos-universal.tar.gz` (optional)

## 2) Checksum generation

- Generate checksums:

```bash
shasum -a 256 peekaboo-mcp-macos-*.tar.gz > checksums.txt
```

## 3) Startup smoke command

```bash
./peekaboo-mcp mcp serve
```

## 4) Provider-default verification

- Run help and confirm MCP-only startup path is shown:

```bash
./peekaboo-mcp --help
./peekaboo-mcp mcp --help
```

## 5) MCP tool list output validation

```bash
./peekaboo-mcp mcp tools list
```

- Confirm expected tool names are present and no removed provider command paths are shown.
