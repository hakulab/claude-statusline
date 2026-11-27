# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

[Unreleased]: https://github.com/hakulab/claude-statusline/compare/v1.0.0-rc.1...HEAD

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
