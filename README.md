# claude-statusline

[![CI](https://github.com/hakulab/claude-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/hakulab/claude-statusline/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Fast, non-blocking status line for Claude Code that works out of the box with local `ccusage` tracking, configurable layouts, and optional external cost providers.

```text
my-project main »1 +2 !1 ?3
Opus 5.5 (1M) high | Ctx: 42% (420k/1000k) | Block: $4.50 (2h5m left, $1.75/h) | Today: $8.25 | 14:35
```

- **Zero config required**: works immediately for personal Claude Code subscriptions using `ccusage` for active 5-hour block and daily usage.
- **Non-blocking caching**: refreshes `ccusage` and any external cost providers in detached background processes behind `flock --nonblock` locks with stale-while-revalidate fallback.
- **Lazy execution**: only invokes `git`, `ccusage blocks`, or cost providers when the configured layout uses them.
- **Customizable**: arrange built-in segments (`dir`, `git`, `model`, `context`, `session`, `mode`, `block`, `today`, `time`) across any number of rows, add model aliases, or plug in HTTP/command cost providers.

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

Outside Nix, clone the repository and run `src/claude-statusline.nu` directly with Nushell:

```bash
git clone https://github.com/hakulab/claude-statusline ~/.local/share/claude-statusline
nu --no-config-file ~/.local/share/claude-statusline/src/claude-statusline.nu --help
```

Runtime requirements: `nu` (Nushell), `bash`, `curl`, `flock`, `git`, and optionally `ccusage` for block and daily usage tracking.

## Claude Code Setup

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

No configuration file is needed for personal Claude Code usage. To customize rows, separators, model aliases, Home Manager `programs.claude-statusline.settings`, or external HTTP/command cost providers, see [docs/configuration.md](docs/configuration.md).

## Development

```bash
nix develop -c run-hooks
nix flake check
```

## License

Copyright (c) 2026 [Hakula](https://hakula.xyz). Licensed under the [MIT License](LICENSE).
