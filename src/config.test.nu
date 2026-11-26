#!/usr/bin/env nu

# ==================================================================================================
# Config and Time Helper Tests
# ==================================================================================================

use std/assert
use ./config.nu [
  active-cost-sources
  default-config
  load-config
  should-show-block
  source-matches
]
use ./time.nu [duration-seconds parse-duration render-template]

def "test parse-duration normalizes shorthand and falls back on invalid values" [] {
  assert equal (parse-duration "60s" 10sec) 60sec
  assert equal (parse-duration "15m" 10sec) 15min
  assert equal (parse-duration "2h" 10sec) 2hr
  assert equal (parse-duration "30sec" 10sec) 30sec
  assert equal (parse-duration 45 10sec) 45sec
  assert equal (parse-duration "invalid" 10sec) 10sec
  assert equal (parse-duration null 10sec) 10sec
  assert equal (duration-seconds 5sec) 5
}

def "test render-template substitutes all placeholders" [] {
  let vars = {
    start_utc: "2026-11-26T00:00:00Z"
    end_utc: "2026-11-26T23:59:59Z"
    date: "2026-11-26"
    start_unix: "1795564800"
    end_unix: "1795651199"
  }
  let out = (
    render-template "from={start_utc}&to={end_utc}&d={date}&s={start_unix}&e={end_unix}" $vars
  )
  assert equal $out (
    "from=2026-11-26T00:00:00Z&to=2026-11-26T23:59:59Z&d=2026-11-26&s=1795564800&e=1795651199"
  )
}

def "test load-config returns defaults when default path is absent" [] {
  let dir = (mktemp --directory)
  let cfg = with-env {XDG_CONFIG_HOME: $dir} { load-config }
  assert equal $cfg (default-config)
}

def "test load-config merges TOML settings and cost sources" [] {
  let dir = (mktemp --directory)
  let path = ($dir | path join "config.toml")
  let toml = '
    [defaults]
    cache_ttl = "30s"
    max_stale = "10m"
    timeout = "3s"

    [local]
    provider = "ccusage"
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
  assert equal $cfg.models {"claude-opus-4-6": "Opus 4.6"}
  assert equal ($cfg.cost_sources | length) 1
  assert equal $cfg.cost_sources.0.behavior {
    show_block: false
    cache_ttl: 90sec
    max_stale: 10min
  }

  let matched = (
    active-cost-sources $cfg {
      ANTHROPIC_BASE_URL: "https://api.example.com/v1"
      BILLING_ENABLED: "1"
    }
  )
  assert equal ($matched | length) 1
  assert equal (should-show-block $cfg $matched) false
}

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
    BILLING_TOKEN: ""
  })
}
