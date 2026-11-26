# claude-statusline

Modular, non-blocking Claude Code statusline with stale-while-revalidate caching and pluggable cost providers.

## Output

```text
my-project main »1 +2 !1 ?3
Opus 4.6 (1M) high | Ctx: 42% (420k/1000k) | Block: $4.50 (2h5m left, $1.75/h) | Today: $8.25 | 14:35
```

- **Row 1**: current directory basename (or `~` for `$HOME`) and Git branch with ahead/behind, staged, modified, and untracked counts.
- **Row 2**: model name (with optional alias map, `(1M)` suffix, and effort level), context window usage, active billing block (when enabled), daily spend (`Today: $local` or `Today: $local / $remote`), and local `HH:MM` clock.

All expensive queries (`ccusage`, HTTP endpoints, external commands) run asynchronously behind per-target `flock --nonblock` locks with stale-while-revalidate caching, so the statusline renders without blocking Claude Code.

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
      defaults = {
        cache_ttl = "60s";
        max_stale = "15m";
        timeout = "5s";
      };

      models."claude-opus-4-6" = "Opus 4.6";

      cost_sources = [
        {
          id = "billing";
          match.env_prefix.ANTHROPIC_BASE_URL = "https://api.example.com";
          source = {
            type = "http";
            url = "https://billing.example.com/v1/usage";
            query = {
              start = "{start_utc}";
              end = "{end_utc}";
            };
            auth = {
              type = "bearer_file";
              path = "/run/secrets/billing-token";
            };
            extract = [ "usage" "total_usd" ];
          };
          behavior.show_block = false;
        }
      ];
    };
  };
}
```

Then point Claude Code's `statusLine.command` in `~/.claude/settings.json` to `claude-statusline` (or `${lib.getExe config.programs.claude-statusline.package}`).

### Overlay or Package

```bash
nix run github:hakulab/claude-statusline -- --help
```

## Configuration

By default, `claude-statusline` reads `${XDG_CONFIG_HOME:-~/.config}/claude-statusline/config.toml` (override with `--config <path>`). Every section is optional.

```toml
[defaults]
cache_ttl = "60s"
max_stale = "15m"
timeout = "5s"

[local]
provider = "ccusage" # "ccusage" or "none"
show_block = true

[models]
"claude-opus-4-6" = "Opus 4.6"

[[cost_sources]]
id = "billing"

[cost_sources.match]
env_prefix = { ANTHROPIC_BASE_URL = "https://api.example.com" }
env_exists = ["BILLING_ENABLED"]

[cost_sources.source]
type = "http"
method = "GET"
url = "https://billing.example.com/v1/usage"
query = { start = "{start_utc}", end = "{end_utc}" }
headers = { Accept = "application/json" }
auth = { type = "bearer_file", path = "/path/to/token" }
ca_file = "/path/to/ca-bundle.crt"
no_proxy = false
extract = ["usage", "total_usd"]
timeout = "5s"

[cost_sources.behavior]
show_block = false
cache_ttl = "60s"
max_stale = "15m"
```

### Pluggable cost sources

- **Matching**: `match.env_prefix` checks environment variable prefixes (enforcing a `/` or exact boundary for `http://` and `https://` URLs), and `match.env_exists` requires non-empty environment variables.
- **HTTP provider** (`type = "http"`): queries an endpoint with `curl`, passing credentials via `--variable` and `--expand-header` so secrets never appear in argv. Supported `auth.type` values: `bearer_file`, `header_file` (with `header`), `bearer_env` (with `env`), or `none`. Missing or empty credentials skip the query gracefully.
- **Command provider** (`type = "command"`): runs `argv` with a timeout, parsing stdout either as a plain float USD value or via the JSON `extract` path.
- **Template variables**: `{start_utc}`, `{end_utc}`, `{date}` (`YYYY-MM-DD`), `{date_compact}` (`YYYYMMDD`), `{start_unix}`, and `{end_unix}` are expanded in HTTP URLs, query parameters, headers, and command `argv` using the local calendar day.

## Development

```bash
nix develop -c run-hooks
nix flake check
```
