# claude-statusline

Modular, non-blocking Claude Code statusline with stale-while-revalidate caching and pluggable cost providers.

```text
my-project main »1 +2 !1 ?3
Opus 5.5 (1M) high | Ctx: 42% (420k/1000k) | Block: $4.50 (2h5m left, $1.75/h) | Today: $8.25 | 14:35
```

- **Configurable layout**: arrange built-in segments (`dir`, `git`, `model`, `context`, `session`, `mode`, `block`, `today`, `time`) across any number of rows with custom separators.
- **Lazy execution**: skips `git` when `git` is omitted, skips `ccusage blocks` when `block` is omitted or disabled, and skips all cost providers when neither `block` nor `today` is configured.
- **Non-blocking caching**: expensive queries (`ccusage`, HTTP endpoints, external commands) refresh in detached background processes behind per-target `flock --nonblock` locks with stale-while-revalidate fallback.
- **Pluggable cost providers**: combine local `ccusage` totals with environment-matched HTTP or command providers without exposing credentials in argv.

## Installation

### Nix Flake / Home Manager

Add the flake input and enable the Home Manager module:

```nix
{
  inputs.claude-statusline.url = "github:hakulab/claude-statusline";

  # In your Home Manager configuration:
  imports = [ inputs.claude-statusline.homeModules.default ];

  programs.claude-statusline = {
    enable = true;
    settings = {
      layout.rows = [
        [ "dir" "git" ]
        [ "model" "context" "block" "today" "time" ]
      ];
      models = {
        "claude-opus-5-5" = "Opus 5.5";
        "claude-sonnet-5-5" = "Sonnet 5.5";
      };
    };
  };
}
```

### Standalone Nix

```bash
nix profile install github:hakulab/claude-statusline
```

Or run directly without installing:

```bash
nix run github:hakulab/claude-statusline -- --help
```

### Manual

Clone this repository and make `src/claude-statusline.nu` executable on your `PATH`. Runtime requirements: `nu` (Nushell), `bash`, `curl`, `flock`, `git`, and optionally `ccusage` for local usage tracking.

### Claude Code Setup

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

By default, `claude-statusline` reads `${XDG_CONFIG_HOME:-~/.config}/claude-statusline/config.toml` (override with `--config <path>`). Every section is optional:

```toml
[defaults]
cache_ttl = "60s"
max_stale = "15m"
timeout = "5s"

[layout]
rows = [
  ["dir", "git"],
  ["model", "context", "block", "today", "time"],
]
separator = " | "

[models]
"claude-opus-5-5" = "Opus 5.5"
"claude-sonnet-5-5" = "Sonnet 5.5"
```

See [docs/configuration.md](docs/configuration.md) for the complete reference covering all sections, built-in segments, template variables, HTTP and command cost providers, and examples.

## Development

```bash
nix develop -c run-hooks
nix flake check
```
