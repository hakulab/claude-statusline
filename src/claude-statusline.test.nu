#!/usr/bin/env nu

# ==================================================================================================
# Claude Code Status Line Integration Tests
# ==================================================================================================

use std/assert
use ./providers/ccusage.nu [CCUSAGE_SPEC DAILY_SPEC]

const SCRIPT_DIR = path self "."
const SCRIPT = ($SCRIPT_DIR | path join "claude-statusline.nu")

const API_BASE_URL = "https://api.example.com"
const BILLING_URL = "https://billing.example.com/v1/usage"
const BILLING_SPEC = {
  cache_name: "statusline-source-billing.json"
  lock_name: "statusline-source-billing.lock"
  refresh: "source:billing"
  fields: [
    "date"
    "has_cost"
    "daily_cost"
  ]
}

def utc-today []: nothing -> string {
  date now | date to-timezone "UTC" | format date "%Y%m%d"
}

def cached-usage [today: string]: nothing -> record {
  {
    date: $today
    has_block: true
    has_daily: true
    block_cost: 4.5
    remaining_minutes: 125
    burn_rate: 1.75
    daily_cost: 8.25
  }
}

def refreshed-usage [today: string]: nothing -> record {
  {
    date: $today
    has_daily: true
    daily_cost: 40.75
    has_block: true
    block_cost: 12.5
    remaining_minutes: 185
    burn_rate: 3.25
  }
}

def cached-daily [today: string]: nothing -> record {
  {
    date: $today
    has_daily: true
    daily_cost: 8.25
  }
}

def refreshed-daily [today: string]: nothing -> record {
  {
    date: $today
    has_daily: true
    daily_cost: 40.75
  }
}

def cached-remote [today: string]: nothing -> record {
  {
    date: $today
    has_cost: true
    daily_cost: 50.0
  }
}

def refreshed-remote [today: string]: nothing -> record {
  {
    date: $today
    has_cost: true
    daily_cost: 198.11
  }
}

def expected-flock-call [
  cache_dir: path
  config: path
  lock_name: string
  target: string
]: nothing -> record {
  {
    lock: ($cache_dir | path join $lock_name)
    command: [
      $nu.current-exe
      "--no-config-file"
      $SCRIPT
      "--config" $config
      "--cache-dir" $cache_dir
      "--refresh" $target
    ]
  }
}

def blocks-call []: nothing -> record {
  {
    args: [
      "claude"
      "blocks"
      "--active"
      "--json"
      "--offline"
    ]
    lock_exists: true
  }
}

def daily-call [today: string]: nothing -> record {
  {
    args: [
      "claude"
      "daily"
      "--since" $today
      "--until" $today
      "--json"
      "--offline"
    ]
    lock_exists: true
  }
}

def refresh-calls [today: string]: nothing -> list<record> {
  [
    (blocks-call)
    (daily-call $today)
  ]
}

def read-calls [log: path]: nothing -> list<record> {
  if ($log | path exists) {
    open $log | from json --objects
  } else {
    []
  }
}

def statusline-fields [output: string]: nothing -> record {
  let columns = (
    $output
    | ansi strip
    | lines
    | get -o 1
    | default ""
    | split row " | "
  )
  {
    block: ($columns | where ($it | str starts-with "Block:") | first | default "")
    daily: ($columns | where ($it | str starts-with "Today:") | first | default "")
  }
}

def invoke-statusline [
  dir: path
  --ccusage-mode: string = "success"
  --curl-mode: string = "success"
  --base-url: string = ""
  --no-token
  --no-ca
  --tz: string = "UTC"
  --fail-mv
  --lock-held
  --async
  --extra-config: record = {}
  --extra-input: record = {}
  --extra-path: string = ""
]: nothing -> record {
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let ccusage_lock = ($cache_dir | path join $CCUSAGE_SPEC.lock_name)
  let daily_lock = ($cache_dir | path join $DAILY_SPEC.lock_name)
  let remote_lock = ($cache_dir | path join $BILLING_SPEC.lock_name)
  let ccusage_log = ($dir | path join "ccusage-calls.jsonl")
  let curl_log = ($dir | path join "curl-calls.jsonl")
  let flock_log = ($dir | path join "flock-calls.jsonl")
  let config = ($dir | path join "config.toml")
  let cwd = ($dir | path join "work")
  mkdir $cwd

  let token_file = ($dir | path join "billing-token")
  if not $no_token {
    "test-billing-token" | save --force --raw $token_file
  }
  let ca_file = ($dir | path join "ca-bundle.crt")
  if not $no_ca {
    "dummy-ca" | save --force --raw $ca_file
  }

  let base_cfg = {
    defaults: {
      cache_ttl: "60s"
      max_stale: "15m"
      timeout: "5s"
    }
    local: {
      provider: "ccusage"
    }
    models: {
      "claude-opus-5-5": "Opus 5.5"
    }
    cost_sources: [
      {
        id: "billing"
        match: {
          env_prefix: {
            ANTHROPIC_BASE_URL: $API_BASE_URL
          }
        }
        source: {
          type: "http"
          url: $BILLING_URL
          query: {
            start: "{start_utc}"
            end: "{end_utc}"
            scope: "user"
          }
          auth: {
            type: "bearer_file"
            path: $token_file
          }
          ca_file: $ca_file
          no_proxy: true
          extract: ["usage" "total_usd"]
        }
        behavior: {
          show_block: false
        }
      }
    ]
  }
  let merged_cfg = ($base_cfg | merge $extra_config)
  ($merged_cfg | to toml | save --force --raw $config)

  let is_remote = (
    ($base_url | str trim --right --char "/") == $API_BASE_URL
    or ($base_url | str starts-with $"($API_BASE_URL)/")
  )
  let has_block_segment = (
    "block" in ($merged_cfg.layout?.rows? | default [["block"]] | flatten)
  )
  let expected_ccusage_lock = if $is_remote or (not $has_block_segment) {
    $daily_lock
  } else {
    $ccusage_lock
  }
  let sync_args = if $async { [] } else { ["--sync-refresh"] }
  let path_list = if ($extra_path | is-not-empty) {
    $env.PATH | prepend $env.NU_TEST_STUBS | prepend $extra_path
  } else {
    $env.PATH | prepend $env.NU_TEST_STUBS
  }

  let payload = (
    {
      workspace: {current_dir: $cwd}
      cost: {total_cost_usd: 1.23}
    }
    | merge $extra_input
  )

  let run = with-env {
    ANTHROPIC_BASE_URL: $base_url
    CCUSAGE_MODE: $ccusage_mode
    CURL_LOG: $curl_log
    CURL_MODE: $curl_mode
    FLOCK_LOG: $flock_log
    PATH: $path_list
    STUB_FLOCK_HELD: (if $lock_held { "1" } else { "0" })
    STUB_LOCK: $expected_ccusage_lock
    STUB_LOG: $ccusage_log
    STUB_MV_FAIL: (if $fail_mv { "1" } else { "0" })
    STUB_REMOTE_LOCK: $remote_lock
    TZ: $tz
  } {
    (
      $payload
      | to json
      | ^$nu.current-exe
        --no-config-file
        $SCRIPT
        --config $config
        --cache-dir $cache_dir
        ...$sync_args
      | complete
    )
  }

  {
    cache_dir: $cache_dir
    ccusage_cache: ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
    daily_cache: ($cache_dir | path join $DAILY_SPEC.cache_name)
    remote_cache: ($cache_dir | path join $BILLING_SPEC.cache_name)
    ccusage_lock: $ccusage_lock
    daily_lock: $daily_lock
    remote_lock: $remote_lock
    config: $config
    token_file: $token_file
    ca_file: $ca_file
    run: $run
    calls: (read-calls $ccusage_log)
    curl_calls: (read-calls $curl_log)
    flock_calls: (read-calls $flock_log)
    fields: (statusline-fields $run.stdout)
    lines: ($run.stdout | ansi strip | lines)
    temporary_files: (ls $cache_dir | where ($it.name | str ends-with ".tmp") | get name)
  }
}

def assert-stale-preserved [result: record, original: string] {
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.flock_calls [
    (expected-flock-call $result.cache_dir $result.config $CCUSAGE_SPEC.lock_name "ccusage")
  ]
  assert equal $result.fields {
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
  assert equal (open --raw $result.ccusage_cache) $original
  assert equal $result.temporary_files []
  assert ($result.ccusage_lock | path exists)
}

# --------------------------------------------------------------------------------------------------
# Default Layout and Caching
# --------------------------------------------------------------------------------------------------

def "test fresh cache skips flock, ccusage, and curl and omits Sess" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  (cached-usage $today) | save ($cache_dir | path join $CCUSAGE_SPEC.cache_name)

  let result = (invoke-statusline $dir)
  assert equal $result.run.exit_code 0 $result.run.stderr

  assert equal $result.flock_calls []
  assert equal $result.calls []
  assert equal $result.curl_calls []
  assert not ($result.lines.1 | str contains "Sess:")
  assert equal $result.fields {
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
}

def "test stale cache serves stale immediately and refreshes cache for next render" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  touch -d "5 minutes ago" $cache

  let first = (invoke-statusline $dir)
  assert equal $first.run.exit_code 0 $first.run.stderr
  assert equal $first.flock_calls [
    (expected-flock-call $first.cache_dir $first.config $CCUSAGE_SPEC.lock_name "ccusage")
  ]
  assert equal $first.calls (refresh-calls $today)
  assert equal $first.curl_calls []
  assert equal $first.fields {
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
  assert equal (open $first.ccusage_cache) (refreshed-usage $today)
  assert ($first.ccusage_lock | path exists)

  let second = (invoke-statusline $dir)
  assert equal $second.run.exit_code 0 $second.run.stderr
  assert equal $second.fields {
    block: "Block: $12.50 (3h5m left, $3.25/h)"
    daily: "Today: $40.75"
  }
}

def "test query and publication failures preserve stale cache without temporary files" [] {
  let today = (utc-today)
  for case in [
    {
      mode: "fail-blocks"
      fail_mv: false
      expected_calls: [(blocks-call)]
    }
    {
      mode: "fail-daily"
      fail_mv: false
      expected_calls: (refresh-calls $today)
    }
    {
      mode: "success"
      fail_mv: true
      expected_calls: (refresh-calls $today)
    }
  ] {
    let dir = (mktemp --directory)
    let cache_dir = ($dir | path join "cache")
    mkdir $cache_dir
    let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
    (cached-usage $today) | save $cache
    let original = (open --raw $cache)
    touch -d "5 minutes ago" $cache

    let result = (invoke-statusline $dir --ccusage-mode $case.mode --fail-mv=$case.fail_mv)
    assert-stale-preserved $result $original
    assert equal $result.calls $case.expected_calls
  }
}

def "test held lock respects max-stale bound and renders no usage when uncached" [] {
  let today = (utc-today)
  for case in [
    {
      age: "5 minutes ago"
      expected_block: "Block: $4.50 (2h5m left, $1.75/h)"
      expected_daily: "Today: $8.25"
    }
    {
      age: "16 minutes ago"
      expected_block: ""
      expected_daily: ""
    }
  ] {
    let dir = (mktemp --directory)
    let cache_dir = ($dir | path join "cache")
    mkdir $cache_dir
    let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
    (cached-usage $today) | save $cache
    touch -d $case.age $cache

    let result = (invoke-statusline $dir --lock-held)
    assert equal $result.run.exit_code 0 $result.run.stderr
    assert equal $result.calls []
    assert equal $result.fields {
      block: $case.expected_block
      daily: $case.expected_daily
    }
  }

  let empty_dir = (mktemp --directory)
  let uncached = (invoke-statusline $empty_dir --lock-held)
  assert equal $uncached.run.exit_code 0 $uncached.run.stderr
  assert equal $uncached.fields {
    block: ""
    daily: ""
  }
}

# --------------------------------------------------------------------------------------------------
# Custom Layout and Optional Segments
# --------------------------------------------------------------------------------------------------

def "test custom layout renders session, mode, custom separator, and per-row separators" [] {
  let dir = (mktemp --directory)
  let extra_cfg = {
    layout: {
      rows: [
        ["dir" "mode"]
        ["model" "session" "context"]
      ]
      separator: " · "
      separators: [" / "]
    }
  }
  let extra_in = {
    model: {
      id: "claude-opus-5-5[1m]"
      display_name: "claude-opus-5-5[1m]"
    }
    context_window: {
      context_window_size: 1000000
      current_usage: {
        input_tokens: 420000
      }
    }
    effort: {
      level: "high"
    }
    vim: {
      mode: "NORMAL"
    }
  }

  let result = (invoke-statusline $dir --extra-config $extra_cfg --extra-input $extra_in)
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.lines [
    "work / NORMAL"
    "Opus 5.5 (1M) high · Sess: $1.23 · Ctx: 42% (420k/1000k)"
  ]
}

# --------------------------------------------------------------------------------------------------
# Lazy On-Demand Execution
# --------------------------------------------------------------------------------------------------

def "test layout without git skips invoking git binary" [] {
  let dir = (mktemp --directory)
  let spy_bin = ($dir | path join "spy-bin")
  let git_log = ($dir | path join "git-called")
  mkdir $spy_bin
  let git_spy = ($spy_bin | path join "git")
  $"#!($nu.current-exe) --no-config-file\n\"called\" | save --append ($git_log | to nuon)\n"
  | save --force --raw $git_spy
  ^chmod +x $git_spy

  let extra_cfg = {
    layout: {
      rows: [
        ["dir"]
        ["context" "time"]
      ]
    }
  }
  let result = (invoke-statusline $dir --extra-config $extra_cfg --extra-path $spy_bin)
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert not ($git_log | path exists)
}

def "test layout without block skips ccusage blocks and queries daily only" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let extra_cfg = {
    layout: {
      rows: [
        ["dir"]
        ["context" "today"]
      ]
    }
  }
  let first = (invoke-statusline $dir --extra-config $extra_cfg)
  assert equal $first.run.exit_code 0 $first.run.stderr
  assert equal $first.flock_calls [
    (expected-flock-call $first.cache_dir $first.config $DAILY_SPEC.lock_name "ccusage-daily")
  ]
  assert equal $first.calls [(daily-call $today)]

  let second = (invoke-statusline $dir --extra-config $extra_cfg)
  assert equal $second.fields {
    block: ""
    daily: "Today: $40.75"
  }
}

def "test layout without block or today skips ccusage and remote cost providers" [] {
  let dir = (mktemp --directory)
  let extra_cfg = {
    layout: {
      rows: [
        ["dir"]
        ["context" "session" "time"]
      ]
    }
  }
  let result = (
    invoke-statusline $dir
      --base-url $"($API_BASE_URL)/anthropic"
      --extra-config $extra_cfg
  )
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.flock_calls []
  assert equal $result.calls []
  assert equal $result.curl_calls []
  assert ($result.lines.1 | str contains "Sess: $1.23")
  assert equal $result.fields {
    block: ""
    daily: ""
  }
}

# --------------------------------------------------------------------------------------------------
# Remote and Command Cost Sources
# --------------------------------------------------------------------------------------------------

def "test http cost source skips blocks, queries endpoint, and renders combined Today" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let utc_date = (date now | date to-timezone "UTC" | format date "%Y-%m-%d")
  let base_url = $"($API_BASE_URL)/anthropic"

  let first = (invoke-statusline $dir --base-url $base_url)
  assert equal $first.run.exit_code 0 $first.run.stderr
  assert equal $first.flock_calls [
    (expected-flock-call $first.cache_dir $first.config $DAILY_SPEC.lock_name "ccusage-daily")
    (expected-flock-call $first.cache_dir $first.config $BILLING_SPEC.lock_name "source:billing")
  ]
  assert equal $first.calls [(daily-call $today)]
  let expected_url = (
    $"($BILLING_URL)"
    + $"?start=($utc_date)T00%3A00%3A00Z&end=($utc_date)T23%3A59%3A59Z&scope=user"
  )
  assert equal $first.curl_calls.0.args.0 $expected_url
  assert equal (open $first.daily_cache) (refreshed-daily $today)
  assert equal (open $first.remote_cache) (refreshed-remote $today)

  let second = (invoke-statusline $dir --base-url $base_url)
  assert equal $second.run.exit_code 0 $second.run.stderr
  assert equal $second.fields {
    block: ""
    daily: "Today: $40.75 / $198.11"
  }
}

def "test http cost source converts non-UTC local day window and skips missing token" [] {
  let tz_dir = (mktemp --directory)
  let tz_res = (
    invoke-statusline $tz_dir
      --base-url $"($API_BASE_URL)/anthropic"
      --tz "UTC-8"
      --no-ca
  )
  assert equal $tz_res.run.exit_code 0 $tz_res.run.stderr
  let curl_args = $tz_res.curl_calls.0.args
  assert ($curl_args.0 | str contains "T16%3A00%3A00Z&end=")
  assert ($curl_args.0 | str ends-with "T15%3A59%3A59Z&scope=user")
  assert not ("--cacert" in $curl_args)

  let no_tok_dir = (mktemp --directory)
  let no_tok = (
    invoke-statusline $no_tok_dir
      --base-url $"($API_BASE_URL)/anthropic"
      --no-token
  )
  assert equal $no_tok.run.exit_code 0 $no_tok.run.stderr
  assert equal $no_tok.curl_calls []
  assert equal ($no_tok.flock_calls | length) 1
}

def "test http fallback renders single Today and non-matching URL stays local" [] {
  let dir_local = (mktemp --directory)
  let base_url = $"($API_BASE_URL)/anthropic"
  invoke-statusline $dir_local --base-url $base_url --curl-mode "fail" | ignore
  let local_only = (invoke-statusline $dir_local --base-url $base_url --curl-mode "fail")
  assert equal $local_only.fields {
    block: ""
    daily: "Today: $40.75"
  }

  let dir_unmatched = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir_unmatched | path join "cache")
  mkdir $cache_dir
  (cached-usage $today) | save ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  let unmatched = (
    invoke-statusline $dir_unmatched --base-url $"($API_BASE_URL).evil.test/anthropic"
  )
  assert equal $unmatched.curl_calls []
  assert equal $unmatched.fields {
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
}

def "test command cost source renders Today end-to-end" [] {
  let dir = (mktemp --directory)
  let extra = {
    local: {
      provider: "none"
    }
    cost_sources: [
      {
        id: "cmd-float"
        match: {}
        source: {
          type: "command"
          argv: ["bash" "-c" 'printf "12.34\n"']
        }
      }
    ]
  }
  invoke-statusline $dir --extra-config $extra | ignore
  let rendered = (invoke-statusline $dir --extra-config $extra)
  assert equal $rendered.run.exit_code 0 $rendered.run.stderr
  assert equal $rendered.fields {
    block: ""
    daily: "Today: $12.34"
  }
}

# --------------------------------------------------------------------------------------------------
# Detached Async Refresh
# --------------------------------------------------------------------------------------------------

def "test empty or minimal stdin renders cleanly without error" [] {
  let dir = (mktemp --directory)
  let config = ($dir | path join "config.toml")
  "[layout]\nrows = [[\"dir\", \"git\"], [\"context\", \"time\"]]\n" | save --force --raw $config

  for raw in ["" "{}" "not-json"] {
    let run = (
      $raw
      | ^$nu.current-exe
        --no-config-file
        $SCRIPT
        --config $config
        --cache-dir ($dir | path join "cache")
      | complete
    )
    assert equal $run.exit_code 0 $run.stderr
    assert ($run.stdout | ansi strip | str contains "Ctx: 0%")
  }
}

def "test detached background refresh returns stale cache without blocking" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  touch -d "5 minutes ago" $cache

  let result = (invoke-statusline $dir --async --lock-held)
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.fields {
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
}
