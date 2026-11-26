# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Modular two-row Claude Code statusline renderer with Git status, model alias and effort display, context usage, active block tracking, and daily spend
- Shared stale-while-revalidate caching with `flock --nonblock` locking and detached background refresh
- Pluggable TOML-configured cost providers (`ccusage`, HTTP with `bearer_file`/`header_file`/`bearer_env` auth and template variables, and external commands)
- Nix flake package, overlay, and Home Manager module (`programs.claude-statusline`)
