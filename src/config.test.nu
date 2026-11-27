#!/usr/bin/env nu

# ==================================================================================================
# Configuration Loader and Source Matcher Tests
# ==================================================================================================

use std/assert
use std-rfc/str
use ./config.nu [
  active-cost-sources
  default-config
  default-config-path
  load-config
  row-separator
  should-show-block
  source-matches
]

# --------------------------------------------------------------------------------------------------
# Defaults and Config Loading
# --------------------------------------------------------------------------------------------------

def "test default-config-path falls back when xdg config home is empty" [] {
  let home = "/tmp/fake-home"
  let resolved = with-env {
    HOME: $home
    XDG_CONFIG_HOME: ""
  } {
    default-config-path
  }
  assert equal $resolved ($home | path join ".config/claude-statusline/config.toml")
}

def "test load-config returns defaults when default path is absent" [] {
  let dir = (mktemp --directory)
  let cfg = with-env {XDG_CONFIG_HOME: $dir} { load-config }
  assert equal $cfg (default-config)
  assert equal $cfg.layout {
    rows: [
      ["dir" "git"]
      ["model" "context" "block" "today" "time"]
    ]
    separator: " | "
    separators: []
  }
  assert equal $cfg.theme {
    preset: "ansi"
    overrides: {}
  }
}

def "test load-config merges TOML defaults, layout, models, and cost sources" [] {
  let dir = (mktemp --directory)
  let path = ($dir | path join "config.toml")
  let toml = (
    '
    [defaults]
    cache_ttl = "30s"
    max_stale = "10m"
    timeout = "3s"

    [layout]
    rows = [
      ["dir", "git", "mode"],
      ["model", "context", "session", "today", "time"],
    ]
    separator = " · "
    separators = [" "]

    [theme]
    preset = "catppuccin-latte"

    [theme.overrides]
    warning = "#fe640b"
    accent = { fg = "#1e66f5", bold = false }

    [local]
    provider = "ccusage"

    [models]
    "claude-opus-5-5" = "Opus 5.5"

    [[cost_sources]]
    id = "billing"

    [cost_sources.match]
    env_prefix = { ANTHROPIC_BASE_URL = "https://api.example.com" }
    env_exists = ["BILLING_ENABLED"]

    [cost_sources.source]
    type = "http"
    url = "https://billing.example.com/v1/usage"
    extract = ["usage", "total_usd"]

    [cost_sources.behavior]
    show_block = false
    cache_ttl = "90s"
    '
    | str dedent
  )
  $toml | save --force --raw $path

  let cfg = (load-config $path)
  assert equal $cfg.defaults {
    cache_ttl: 30sec
    max_stale: 10min
    timeout: 3sec
  }
  assert equal $cfg.layout {
    rows: [
      ["dir" "git" "mode"]
      ["model" "context" "session" "today" "time"]
    ]
    separator: " · "
    separators: [" "]
  }
  assert equal $cfg.theme {
    preset: "catppuccin-latte"
    overrides: {
      warning: "#fe640b"
      accent: {
        fg: "#1e66f5"
        bold: false
      }
    }
  }
  assert equal $cfg.models {"claude-opus-5-5": "Opus 5.5"}
  assert equal ($cfg.cost_sources | length) 1
  assert equal $cfg.cost_sources.0.behavior {
    show_block: false
    cache_ttl: 90sec
    max_stale: 10min
  }
}

def "test load-config errors on missing explicit file or non-record payload" [] {
  let dir = (mktemp --directory)
  let missing = ($dir | path join "missing.toml")
  let missing_err = try {
    load-config $missing
    ""
  } catch {|e|
    $e.msg
  }
  assert ($missing_err | str contains "config file not found")

  let list_file = ($dir | path join "list.json")
  [1 2 3] | to json | save --force --raw $list_file
  let shape_err = try {
    load-config $list_file
    ""
  } catch {|e|
    $e.msg
  }
  assert ($shape_err | str contains "must contain a table or record")
}

def "test load-config preserves unknown theme keys and marks non-record theme sections" [] {
  let dir = (mktemp --directory)
  let unknown_key = ($dir | path join "unknown-theme-key.toml")
  (
    '
    [theme]
    base = "catppuccin-latte"
    '
    | str dedent
    | save --force --raw $unknown_key
  )
  let unknown_cfg = (load-config $unknown_key)
  assert equal $unknown_cfg.theme {
    base: "catppuccin-latte"
    preset: "ansi"
    overrides: {}
  }

  let bad_theme = ($dir | path join "bad-theme.toml")
  'theme = "catppuccin-latte"' | save --force --raw $bad_theme
  let bad_cfg = (load-config $bad_theme)
  assert equal $bad_cfg.theme {
    preset: "ansi"
    overrides: {}
    invalid_section: "string"
  }
}

# --------------------------------------------------------------------------------------------------
# Cost Source Matching and Block Visibility
# --------------------------------------------------------------------------------------------------

def "test source-matches enforces URL boundary and env-exists" [] {
  let entry = {
    id: "billing"
    match: {
      env_prefix: {
        ANTHROPIC_BASE_URL: "https://api.example.com"
      }
      env_exists: ["BILLING_TOKEN"]
    }
  }
  let cases = [
    {
      name: "exact URL match"
      env: {
        ANTHROPIC_BASE_URL: "https://api.example.com"
        BILLING_TOKEN: "present"
      }
      expected: true
    }
    {
      name: "path suffix under URL prefix"
      env: {
        ANTHROPIC_BASE_URL: "https://api.example.com/anthropic"
        BILLING_TOKEN: "present"
      }
      expected: true
    }
    {
      name: "lookalike host suffix rejected"
      env: {
        ANTHROPIC_BASE_URL: "https://api.example.com.evil.test/anthropic"
        BILLING_TOKEN: "present"
      }
      expected: false
    }
    {
      name: "blank required env var rejected"
      env: {
        ANTHROPIC_BASE_URL: "https://api.example.com/anthropic"
        BILLING_TOKEN: "   "
      }
      expected: false
    }
  ]
  for case in $cases {
    assert equal (source-matches $entry $case.env) $case.expected $case.name
  }
}

def "test active-cost-sources filters empty ids and unmatched rules" [] {
  let cfg = {
    cost_sources: [
      {
        id: ""
        match: {}
      }
      {
        id: "matched"
        match: {env_exists: ["ENABLE_A"]}
      }
      {
        id: "unmatched"
        match: {env_exists: ["ENABLE_B"]}
      }
    ]
  }
  let matched = (active-cost-sources $cfg {ENABLE_A: "1"})
  assert equal ($matched | get id) ["matched"]
}

def "test should-show-block hides block when any matched source disables it" [] {
  let hide = {behavior: {show_block: false}}
  let inherit_opt = {behavior: {show_block: null}}
  let show = {behavior: {show_block: true}}

  assert equal (should-show-block []) true
  assert equal (should-show-block [$inherit_opt $show]) true
  assert equal (should-show-block [$hide]) false
  assert equal (should-show-block [$show $hide]) false
}

# --------------------------------------------------------------------------------------------------
# Layout Separators
# --------------------------------------------------------------------------------------------------

def "test row-separator applies defaults, custom separator, and per-row overrides" [] {
  let default_layout = (default-config).layout
  assert equal (row-separator $default_layout 0) " "
  assert equal (row-separator $default_layout 1) " | "
  assert equal (row-separator $default_layout 2) " | "

  let custom_sep = {
    rows: [["dir" "git"] ["model" "context"] ["today" "time"]]
    separator: " · "
    separators: []
  }
  assert equal (row-separator $custom_sep 0) " "
  assert equal (row-separator $custom_sep 1) " · "
  assert equal (row-separator $custom_sep 2) " · "

  let per_row = {
    rows: [["dir" "model"] ["context" "today"] ["time"]]
    separator: " | "
    separators: [" / " " · "]
  }
  assert equal (row-separator $per_row 0) " / "
  assert equal (row-separator $per_row 1) " · "
  assert equal (row-separator $per_row 2) " | "
}
