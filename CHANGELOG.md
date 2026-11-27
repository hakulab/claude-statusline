# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

[Unreleased]: https://github.com/hakulab/claude-statusline/compare/v1.0.0-rc.2...HEAD

## [1.0.0-rc.2] - 2026-11-27

### Added

- _(theme)_ Configurable `[theme]` presets (`catppuccin-mocha` default, `catppuccin-latte`, `ansi`, and `monochrome`) and per-slot `[theme.overrides]` supporting 6-digit hex, ANSI 16 named colors, 256-color indices, `reset` / `default`, and SGR modifiers (`bold`, `dim`, `italic`, `underlined`, `reversed`); the default palette switches from ANSI 16 to 24-bit `catppuccin-mocha` (`preset = "ansi"` restores terminal-native 16-color output) ([#5](https://github.com/hakulab/claude-statusline/pull/5))
- _(theme)_ `NO_COLOR` environment variable support that disables all ANSI escape sequences when set to a non-empty value ([#5](https://github.com/hakulab/claude-statusline/pull/5))

[1.0.0-rc.2]: https://github.com/hakulab/claude-statusline/compare/v1.0.0-rc.1...v1.0.0-rc.2

## [1.0.0-rc.1] - 2026-11-27

### Added

- Modular Nushell status line renderer for Claude Code with Git status, model alias and effort display, context usage, active block tracking, and daily spend ([#1](https://github.com/hakulab/claude-statusline/pull/1))
- Configurable `[layout]` (`rows`, `separator`, and per-row `separators`) with lazy execution that skips `git`, `ccusage blocks`, and cost providers when their segments are omitted from `rows` ([#2](https://github.com/hakulab/claude-statusline/pull/2))
- Optional `mode` (`vim.mode`) and `session` (`Sess: $X.XX`) built-in segments ([#2](https://github.com/hakulab/claude-statusline/pull/2))
- Shared stale-while-revalidate caching with `flock --nonblock` locking and detached background refresh ([#1](https://github.com/hakulab/claude-statusline/pull/1))
- Pluggable TOML-configured cost providers: local `ccusage`, HTTP endpoints with `bearer_file`, `header_file`, and `bearer_env` auth and template variables, and external commands ([#1](https://github.com/hakulab/claude-statusline/pull/1))
- Nix flake package, overlay (`overlays.default`), and Home Manager module (`programs.claude-statusline`) ([#1](https://github.com/hakulab/claude-statusline/pull/1))
- Configuration reference in `docs/configuration.md` ([#2](https://github.com/hakulab/claude-statusline/pull/2))

[1.0.0-rc.1]: https://github.com/hakulab/claude-statusline/releases/tag/v1.0.0-rc.1
