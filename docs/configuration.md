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

| Key         | Type       | Default | Description                                                      |
| ----------- | ---------- | ------- | ---------------------------------------------------------------- |
| `cache_ttl` | `duration` | `"60s"` | Freshness window before a background refresh is scheduled        |
| `max_stale` | `duration` | `"15m"` | Maximum age of stale cached data served while refreshing         |
| `timeout`   | `duration` | `"5s"`  | Per-request timeout for HTTP and external command cost providers |

Duration values accept shorthand strings (`30s`, `15m`, `2h`), [Nushell durations](https://www.nushell.sh/book/types_of_data.html#durations) (`60sec`, `15min`), or bare numeric seconds (`45`).

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

### `[theme]`

Selects a color preset and optional per-slot style overrides.

| Key         | Type     | Default              | Description                                                                               |
| ----------- | -------- | -------------------- | ----------------------------------------------------------------------------------------- |
| `preset`    | `string` | `"catppuccin-mocha"` | Built-in palette: `"catppuccin-mocha"`, `"catppuccin-latte"`, `"ansi"`, or `"monochrome"` |
| `overrides` | `table`  | `{}`                 | Per-slot style patches applied on top of `preset`                                         |

Built-in presets:

- `"catppuccin-mocha"` (default): 24-bit truecolor dark palette based on [Catppuccin](https://catppuccin.com/palette/) Mocha.
- `"catppuccin-latte"`: 24-bit truecolor light palette based on [Catppuccin](https://catppuccin.com/palette/) Latte.
- `"ansi"`: terminal-native [16-color ANSI](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) palette with terminal-default dim for labels and separators.
- `"monochrome"`: modifier-only styling (`bold`, `dim`, `italic`, `underlined`) with no color hues, readable on any light or dark terminal background.

Invalid preset names or malformed overrides print a warning to stderr and fall back cleanly so the status line continues to render.

Setting `NO_COLOR` to any non-empty value disables all ANSI escape sequences regardless of `[theme]`, following [no-color.org](https://no-color.org/). An unset or empty `NO_COLOR` leaves colors enabled.

#### Semantic slots

| Slot        | Used by                                                          |
| ----------- | ---------------------------------------------------------------- |
| `accent`    | `dir`                                                            |
| `info`      | `model`, `session`, `block` cost, `today`                        |
| `success`   | `git` branch, `context` (< 50%)                                  |
| `warning`   | `git` status marks, `context` (50–79%), `block` remaining / rate |
| `error`     | `context` (≥ 80%)                                                |
| `mode`      | `mode` vim indicator                                             |
| `muted`     | `Ctx:`, `Sess:`, `Block:`, `Today:` labels and `time`            |
| `separator` | Non-whitespace row separator                                     |

#### `[theme.overrides]`

Each key in `[theme.overrides]` names one of the eight semantic slots and accepts either:

- A **bare color string** (`warning = "#fe640b"`), which patches `fg` and preserves the preset's `bg` and modifiers.
- An **inline table** (`accent = { fg = "#1e66f5", bold = false }`), which patches only the listed fields (`fg`, `bg`, `bold`, `dim`, `italic`, `underlined`, `reversed`). Omitted fields inherit from the preset. Setting a modifier to `false` clears it, and setting `fg` or `bg` to `"reset"` (or `"default"`) clears that channel to the terminal default.

When overriding `muted` or `separator` with a hex color on top of the `ansi` or `monochrome` preset, set `dim = false` if you do not want the terminal to dim the RGB value.

Color values are case-insensitive and trim surrounding whitespace:

| Form              | Example      | Description                                                                                                                                |
| ----------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 6-digit hex       | `"#89b4fa"`  | 24-bit truecolor RGB (3-digit `#fff` is rejected)                                                                                          |
| ANSI 16 named     | `"blue"`     | Standard (`black`–`white`) and bright (`bright_black`–`bright_white`) [ANSI colors](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) |
| Indexed 256-color | `"ansi:174"` | [8-bit 256-color](https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit) palette index `0`–`255`                                            |
| Terminal default  | `"reset"`    | Clears `fg` or `bg` to the terminal default (`"default"` is also accepted)                                                                 |

Accepted ANSI 16 names are `black`, `red`, `green`, `yellow`, `blue`, `magenta` (`purple`), `cyan`, `white` (`gray` / `grey`), and their `bright_*` variants (aliases: `dark_gray` / `dark_grey` for `bright_black`, `light_*` for `bright_red`–`bright_white`, and `bright_purple` / `light_purple` for `bright_magenta`).

### `[local]`

Configures the built-in local usage provider ([`ccusage`](https://github.com/ryoppippi/ccusage)).

| Key        | Type     | Default     | Description             |
| ---------- | -------- | ----------- | ----------------------- |
| `provider` | `string` | `"ccusage"` | `"ccusage"` or `"none"` |

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

| Key          | Type       | Default                | Description                                                          |
| ------------ | ---------- | ---------------------- | -------------------------------------------------------------------- |
| `show_block` | `bool`     | `true`                 | Set to `false` to hide the `block` segment while this source matches |
| `cache_ttl`  | `duration` | `[defaults].cache_ttl` | Per-source cache TTL override                                        |
| `max_stale`  | `duration` | `[defaults].max_stale` | Per-source max stale age override                                    |

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

### Theme preset with overrides

```toml
[theme]
preset = "catppuccin-latte"

[theme.overrides]
warning = "#fe640b"
accent = { fg = "#7287fd", bold = false }
muted = { fg = "#5c5f77", italic = true }
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

[[cost_sources]]
id = "custom-cli"

[cost_sources.source]
type = "command"
argv = ["my-billing-cli", "daily", "--date", "{date}", "--json"]
extract = ["totals", "usd"]
```
