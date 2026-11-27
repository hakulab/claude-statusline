# claude-statusline

[![CI](https://github.com/hakulab/claude-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/hakulab/claude-statusline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`claude-statusline` renders a non-blocking status line for Claude Code with local [`ccusage`](https://github.com/ryoppippi/ccusage) tracking, configurable layouts, and optional external cost providers.

```text
my-project main »1 +2 !1 ?3
Opus 5.5 (1M) high | Ctx: 42% (420k/1000k) | Block: $4.50 (2h5m left, $1.75/h) | Today: $8.25 | 14:35
```

- **Zero configuration**: personal Claude Code subscriptions work without a config file, using `ccusage` for active 5-hour block and daily usage.
- **Non-blocking caching**: `ccusage` and external cost providers refresh in detached background processes behind `flock --nonblock` locks while stale cached values are served.
- **Lazy execution**: `git`, `ccusage blocks`, and cost providers run only when the configured layout uses the segments that need them. In non-subscription environments (API keys, custom base URLs, Bedrock, Vertex, or Foundry), `block` is automatically hidden and `ccusage blocks` is skipped.
- **Configurable layout**: arrange [built-in segments](docs/configuration.md#built-in-segments) across any number of rows, add model aliases, or plug in HTTP or command cost providers.
- **Customizable themes**: choose from [built-in presets](docs/configuration.md#theme) (`catppuccin-mocha`, `catppuccin-latte`, `ansi`, `monochrome`), override individual semantic color slots, and disable ANSI output via [`NO_COLOR`](https://no-color.org/).

## Install

### Nix

```bash
nix profile install github:hakulab/claude-statusline
```

Or run directly without installing:

```bash
nix run github:hakulab/claude-statusline -- --help
```

### Home Manager

Add the flake input (`inputs.claude-statusline.url = "github:hakulab/claude-statusline";`), import `inputs.claude-statusline.homeModules.default`, and enable the module:

```nix
programs.claude-statusline.enable = true;
```

### From source

Outside Nix, clone the repository and run `src/claude-statusline.nu` directly with [Nushell](https://www.nushell.sh/):

```bash
git clone https://github.com/hakulab/claude-statusline ~/.local/share/claude-statusline
nu --no-config-file ~/.local/share/claude-statusline/src/claude-statusline.nu --help
```

Runtime requirements: `nu` (Nushell), `bash`, `curl`, `flock`, `git`, and optionally `ccusage` for block and daily usage tracking.

## Claude Code setup

Point `statusLine.command` in `~/.claude/settings.json` to `claude-statusline`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "claude-statusline"
  }
}
```

## Configuration

Personal Claude Code subscriptions work without a configuration file. See [docs/configuration.md](docs/configuration.md) to customize rows, separators, themes, model aliases, Home Manager `programs.claude-statusline.settings`, or external HTTP and command cost providers.

## Development

```bash
nix develop -c run-hooks
nix flake check
```

## License

Copyright (c) 2026 [Hakula](https://hakula.xyz). Licensed under the [MIT License](LICENSE).
