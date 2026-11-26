#!/usr/bin/env nu

# ==================================================================================================
# Configuration Loader and Source Matcher Tests
# ==================================================================================================

use std/assert
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
}

def "test load-config merges TOML defaults, layout, models, and cost sources" [] {
  let dir = (mktemp --directory)
  let path = ($dir | path join "config.toml")
  let toml = '
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

    [local]
    provider = "ccusage"
    show_block = true

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
  } catch {|err| $err.msg }
  assert ($missing_err | str contains "config file not found")

  let list_file = ($dir | path join "list.json")
  "[1, 2, 3]" | save --force --raw $list_file
  let shape_err = try {
    load-config $list_file
    ""
  } catch {|err| $err.msg }
  assert ($shape_err | str contains "must contain a table or record")
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
  assert (source-matches $entry {
    ANTHROPIC_BASE_URL: "https://api.example.com"
    BILLING_TOKEN: "present"
  })
  assert (source-matches $entry {
    ANTHROPIC_BASE_URL: "https://api.example.com/anthropic"
    BILLING_TOKEN: "present"
  })
  assert not (source-matches $entry {
    ANTHROPIC_BASE_URL: "https://api.example.com.evil.test/anthropic"
    BILLING_TOKEN: "present"
  })
  assert not (source-matches $entry {
    ANTHROPIC_BASE_URL: "https://api.example.com/anthropic"
    BILLING_TOKEN: "   "
  })
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

def "test should-show-block applies local default and matched overrides in order" [] {
  let cfg = (default-config)
  assert equal (should-show-block $cfg []) true

  let hide = {behavior: {show_block: false}}
  let inherit_opt = {behavior: {show_block: null}}
  let show = {behavior: {show_block: true}}

  assert equal (should-show-block $cfg [$hide]) false
  assert equal (should-show-block $cfg [$hide $inherit_opt]) false
  assert equal (should-show-block $cfg [$hide $show]) true
}
