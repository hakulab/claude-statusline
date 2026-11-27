# Configuration reference

`claude-statusline` reads `${XDG_CONFIG_HOME:-~/.config}/claude-statusline/config.toml` by default, or any TOML or JSON file passed via `--config <path>`. Every section and key is optional, and omitted keys fall back to the defaults below.

When using the Home Manager module, pass any of these keys under `programs.claude-statusline.settings` to generate `config.toml`:

```nix
programs.claude-statusline = {
  enable = true;
  settings = {
    defaults.cache_ttl = "30s";
    layout.separator = " · ";
  };
};
```

## Sections

### `[defaults]`

Global timing defaults for cache freshness and cost-provider requests.

| Key         | Type     | Default | Description                                                      |
| ----------- | -------- | ------- | ---------------------------------------------------------------- |
| `cache_ttl` | duration | `"60s"` | Freshness window before a background refresh is scheduled        |
| `max_stale` | duration | `"15m"` | Maximum age of stale cached data served while refreshing         |
| `timeout`   | duration | `"5s"`  | Per-request timeout for HTTP and external command cost providers |

Duration values accept shorthand strings (`30s`, `15m`, `2h`), Nushell duration strings (`60sec`, `15min`), or bare numeric seconds (`45`).

### `[layout]`

Controls which segments appear on each row and how segments are joined.

| Key          | Type                 | Default                                                            | Description                                                     |
| ------------ | -------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------- |
| `rows`       | `list<list<string>>` | `[["dir", "git"], ["model", "context", "block", "today", "time"]]` | Segment names arranged by row, omitting empty segments and rows |
| `separator`  | `string`             | `" \| "`                                                           | Default separator for rows after row 0                          |
| `separators` | `list<string>`       | `[]`                                                               | Optional per-row separator overrides indexed from 0             |

Row 0 defaults to `" "` unless overridden by `separators[0]`. Rows beyond the length of `separators` fall back to `separator`. External commands and cost providers run only when a segment that uses them appears in `rows`.

#### Built-in segments

| Name      | Default | Data source                      | Example output                            |
| --------- | ------- | -------------------------------- | ----------------------------------------- |
| `dir`     | Row 0   | `workspace.current_dir`          | `my-project`                              |
| `git`     | Row 0   | `git status`                     | `main »1 +2 !1 ?3`                        |
| `mode`    | Omitted | `vim.mode`                       | `NORMAL`                                  |
| `model`   | Row 1   | `model`, `[models]`, `effort`    | `Opus 5.5 (1M) high`                      |
| `context` | Row 1   | `context_window`                 | `Ctx: 42% (420k/1000k)`                   |
| `session` | Omitted | `cost.total_cost_usd`            | `Sess: $1.23`                             |
| `block`   | Row 1   | `ccusage blocks`                 | `Block: $4.50 (2h5m left, $1.75/h)`       |
| `today`   | Row 1   | `ccusage daily` + `cost_sources` | `Today: $8.25` or `Today: $8.25 / $19.50` |
| `time`    | Row 1   | Local system clock               | `14:35`                                   |

Unknown segment names are ignored.

### `[local]`

Configures the built-in local usage provider.

| Key          | Type     | Default     | Description                                 |
| ------------ | -------- | ----------- | ------------------------------------------- |
| `provider`   | `string` | `"ccusage"` | `"ccusage"` or `"none"`                     |
| `show_block` | `bool`   | `true`      | Fetch and render the active `block` segment |

### `[models]`

Overrides display names for raw model IDs (without any trailing `[1m]` suffix), useful for proxy or custom endpoints. Standard Claude models use Claude Code's `model.display_name` automatically.

```toml
[models]
"acme/reasoning-v2" = "Reasoning v2"
"acme/fast-v1" = "Fast v1"
```

### `[[cost_sources]]`

Defines additional remote or script-backed daily cost providers. Every matching and ready source contributes a value to the `today` segment, joined with `" / "` after any local `ccusage` daily total.

Each entry has four fields:

- `id` (`string`, required): unique identifier for the source
- `match` (table, optional): environment rules that activate this source
- `source` (table, required): provider type (`"http"` or `"command"`) and its parameters
- `behavior` (table, optional): per-source `show_block`, `cache_ttl`, and `max_stale` overrides

#### `[cost_sources.match]`

| Key          | Type            | Description                                          |
| ------------ | --------------- | ---------------------------------------------------- |
| `env_prefix` | `table<string>` | Required prefix for each listed environment variable |
| `env_exists` | `list<string>`  | Environment variables that must be set and non-blank |

HTTP and HTTPS prefixes in `env_prefix` require an exact match or a `/` path boundary.

#### `[cost_sources.source]` (HTTP)

Queries an HTTP endpoint and extracts a numeric USD total from the JSON response.

| Key        | Type            | Default              | Description                                              |
| ---------- | --------------- | -------------------- | -------------------------------------------------------- |
| `type`     | `string`        | required             | `"http"`                                                 |
| `url`      | `string`        | required             | Endpoint URL (supports template variables)               |
| `method`   | `string`        | `"GET"`              | HTTP method                                              |
| `query`    | `table<string>` | `{}`                 | URL query parameters (support template variables)        |
| `headers`  | `table<string>` | `{}`                 | Extra HTTP headers (support template variables)          |
| `auth`     | `table`         | `{}`                 | Credential configuration (see [Auth types](#auth-types)) |
| `ca_file`  | `string`        | `""`                 | Optional CA certificate bundle path                      |
| `no_proxy` | `bool`          | `false`              | Bypass proxy environment variables                       |
| `extract`  | `list<string>`  | required             | JSON key path to the numeric USD total                   |
| `timeout`  | `duration`      | `[defaults].timeout` | Per-source timeout override                              |

##### Auth types

If a configured token file or environment variable is missing or blank, the source is skipped.

| `auth.type`   | Extra fields     | Header sent                             |
| ------------- | ---------------- | --------------------------------------- |
| `none`        | (none)           | No auth header (default)                |
| `bearer_file` | `path`           | `Authorization: Bearer <file contents>` |
| `header_file` | `header`, `path` | `<header>: <file contents>`             |
| `bearer_env`  | `env`            | `Authorization: Bearer <env value>`     |

#### `[cost_sources.source]` (command)

Runs an external command and reads a USD cost from stdout.

| Key       | Type           | Default              | Description                                                      |
| --------- | -------------- | -------------------- | ---------------------------------------------------------------- |
| `type`    | `string`       | required             | `"command"`                                                      |
| `argv`    | `list<string>` | required             | Command and arguments (each element supports template variables) |
| `extract` | `list<string>` | `[]`                 | Optional JSON key path (when empty, stdout is parsed as a float) |
| `timeout` | `duration`     | `[defaults].timeout` | Per-source timeout override                                      |

#### `[cost_sources.behavior]`

| Key          | Type       | Default                | Description                                                     |
| ------------ | ---------- | ---------------------- | --------------------------------------------------------------- |
| `show_block` | `bool`     | `[local].show_block`   | Per-source override for block display while this source matches |
| `cache_ttl`  | `duration` | `[defaults].cache_ttl` | Per-source cache TTL override                                   |
| `max_stale`  | `duration` | `[defaults].max_stale` | Per-source max stale age override                               |

## Template variables

Expanded in HTTP `url`, `query`, `headers`, and command `argv` for the local calendar day:

| Variable         | Example                | Description                      |
| ---------------- | ---------------------- | -------------------------------- |
| `{start_utc}`    | `2026-11-26T00:00:00Z` | Local day start formatted in UTC |
| `{end_utc}`      | `2026-11-26T23:59:59Z` | Local day end formatted in UTC   |
| `{date}`         | `2026-11-26`           | Local date (`YYYY-MM-DD`)        |
| `{date_compact}` | `20261126`             | Local date (`YYYYMMDD`)          |
| `{start_unix}`   | `1795651200`           | Local day start as Unix seconds  |
| `{end_unix}`     | `1795737599`           | Local day end as Unix seconds    |

## Examples

### Compact single-row layout

Omitting `git`, `block`, and `today` skips spawning `git` and `ccusage`:

```toml
[layout]
rows = [["dir", "model", "context", "session", "time"]]
separators = [" · "]
```

### Remote HTTP billing provider

```toml
[[cost_sources]]
id = "billing"

[cost_sources.match]
env_prefix = { ANTHROPIC_BASE_URL = "https://api.example.com" }
env_exists = ["BILLING_ENABLED"]

[cost_sources.source]
type = "http"
url = "https://billing.example.com/v1/usage"
query = { start = "{start_utc}", end = "{end_utc}" }
auth = { type = "bearer_file", path = "/run/secrets/billing-token" }
extract = ["usage", "total_usd"]

[cost_sources.behavior]
show_block = false
cache_ttl = "60s"
max_stale = "15m"
```

### External command provider

```toml
[local]
provider = "none"
show_block = false

[[cost_sources]]
id = "custom-cli"

[cost_sources.source]
type = "command"
argv = ["my-billing-cli", "daily", "--date", "{date}", "--json"]
extract = ["totals", "usd"]
```
