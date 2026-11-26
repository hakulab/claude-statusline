#!/usr/bin/env nu

# ==================================================================================================
# Claude Code Status Line Integration Tests
# ==================================================================================================

use std/assert
use ./cache.nu [write-cache]
use ./providers/ccusage.nu [CCUSAGE_SPEC DAILY_SPEC ccusage-json]
use ./providers/common.nu [source-cache-spec]

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
    sess: ($columns | where ($it | str starts-with "Sess:") | first | default "")
    block: ($columns | where ($it | str starts-with "Block:") | first | default "")
    daily: ($columns | where ($it | str starts-with "Today:") | first | default "")
  }
}

def invoke-statusline [
  dir: path
  --ccusage-mode: string = "success"
  --curl-mode: string = "success"
  --base-url: string = ""
  --auth-type: string = "bearer_file"
  --token-content: string = "test-billing-token"
  --no-token
  --no-ca
  --tz: string = "UTC"
  --fail-mv
  --lock-held
  --async
  --extra-config: record = {}
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
    $token_content | save --force --raw $token_file
  }
  let ca_file = ($dir | path join "ca-bundle.crt")
  if not $no_ca {
    "dummy-ca" | save --force --raw $ca_file
  }

  let auth = match $auth_type {
    "header_file" => {
      type: "header_file"
      header: "X-API-Key"
      path: $token_file
    }
    "bearer_env" => {
      type: "bearer_env"
      env: "BILLING_API_TOKEN"
    }
    _ => {
      type: "bearer_file"
      path: $token_file
    }
  }

  let base_cfg = {
    defaults: {
      cache_ttl: "60s"
      max_stale: "15m"
      timeout: "5s"
    }
    local: {
      provider: "ccusage"
      show_block: true
    }
    models: {}
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
          auth: $auth
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
  ($base_cfg | merge $extra_config | to toml | save --force --raw $config)

  let is_remote = (
    ($base_url | str trim --right --char "/") == $API_BASE_URL
    or ($base_url | str starts-with $"($API_BASE_URL)/")
  )
  let expected_ccusage_lock = if $is_remote { $daily_lock } else { $ccusage_lock }
  let sync_args = if $async { [] } else { ["--sync-refresh"] }
  let env_token = if $no_token { "" } else { $token_content }

  let run = with-env {
    ANTHROPIC_BASE_URL: $base_url
    BILLING_API_TOKEN: $env_token
    CCUSAGE_MODE: $ccusage_mode
    CURL_LOG: $curl_log
    CURL_MODE: $curl_mode
    FLOCK_LOG: $flock_log
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    STUB_FLOCK_HELD: (if $lock_held { "1" } else { "0" })
    STUB_LOCK: $expected_ccusage_lock
    STUB_LOG: $ccusage_log
    STUB_MV_FAIL: (if $fail_mv { "1" } else { "0" })
    STUB_REMOTE_LOCK: $remote_lock
    TZ: $tz
  } {
    (
      {
        workspace: {current_dir: $cwd}
        cost: {total_cost_usd: 1.23}
      }
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
    temporary_files: (ls $cache_dir | where ($it.name | str ends-with ".tmp") | get name)
  }
}

def assert-stale-preserved [result: record, original: string] {
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.flock_calls [
    (expected-flock-call $result.cache_dir $result.config $CCUSAGE_SPEC.lock_name "ccusage")
  ]
  assert equal $result.fields {
    sess: ""
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
  assert equal (open --raw $result.ccusage_cache) $original
  assert equal $result.temporary_files []
  assert ($result.ccusage_lock | path exists)
}

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
  assert equal $result.fields {
    sess: ""
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
    sess: ""
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
  assert equal (open $first.ccusage_cache) (refreshed-usage $today)
  assert ($first.ccusage_lock | path exists)

  let second = (invoke-statusline $dir)
  assert equal $second.run.exit_code 0 $second.run.stderr
  assert equal $second.fields {
    sess: ""
    block: "Block: $12.50 (3h5m left, $3.25/h)"
    daily: "Today: $40.75"
  }
}

def "test blocks query failure preserves stale cache without publishing partial usage" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  let original = (open --raw $cache)
  touch -d "5 minutes ago" $cache

  let result = (invoke-statusline $dir --ccusage-mode "fail-blocks")

  assert-stale-preserved $result $original
  assert equal $result.calls [(blocks-call)]
}

def "test scalar blocks response preserves stale cache without querying daily" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  let original = (open --raw $cache)
  touch -d "5 minutes ago" $cache

  let result = (invoke-statusline $dir --ccusage-mode "scalar-blocks")

  assert-stale-preserved $result $original
  assert equal $result.calls [(blocks-call)]

  let shape_log = ($dir | path join "ccusage-shape.jsonl")
  let shape_error = with-env {
    CCUSAGE_MODE: "scalar-blocks"
    PATH: $env.NU_TEST_STUBS
    STUB_LOCK: $result.ccusage_lock
    STUB_LOG: $shape_log
  } {
    try {
      ccusage-json [blocks --active]
      ""
    } catch {|error|
      $error.msg
    }
  }
  assert equal $shape_error "ccusage blocks --active returned invalid JSON"
  assert equal (read-calls $shape_log) [(blocks-call)]
}

def "test daily query failure preserves stale cache after a successful blocks query" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  let original = (open --raw $cache)
  touch -d "5 minutes ago" $cache

  let result = (invoke-statusline $dir --ccusage-mode "fail-daily")

  assert-stale-preserved $result $original
  assert equal $result.calls (refresh-calls $today)
}

def "test write-cache reports save failure without temporary state" [] {
  let dir = (mktemp --directory)
  let cache_parent = ($dir | path join "not-a-directory")
  touch $cache_parent
  let cache = ($cache_parent | path join $CCUSAGE_SPEC.cache_name)

  let save_error = try {
    write-cache $cache (refreshed-usage (utc-today))
    ""
  } catch {|error|
    $error.msg
  }

  assert equal $save_error "failed to write usage cache"
  assert equal (ls $dir | get name) [$cache_parent]
}

def "test publication failure preserves stale cache and cleans temporary state" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
  (cached-usage $today) | save $cache
  let original = (open --raw $cache)
  touch -d "5 minutes ago" $cache

  let result = (invoke-statusline $dir --fail-mv)

  assert-stale-preserved $result $original
  assert equal $result.calls (refresh-calls $today)
}

def "test held lock respects stale fallback age bound" [] {
  let today = (utc-today)
  let cases = [
    [name age expected_stale];
    ["five-minute stale" "5 minutes ago" true]
    ["sixteen-minute expired" "16 minutes ago" false]
  ]
  for case in $cases {
    let dir = (mktemp --directory)
    let cache_dir = ($dir | path join "cache")
    mkdir $cache_dir
    let cache = ($cache_dir | path join $CCUSAGE_SPEC.cache_name)
    (cached-usage $today) | save $cache
    touch -d $case.age $cache

    let result = (invoke-statusline $dir --lock-held)

    let expected_fields = if $case.expected_stale {
      {
        sess: ""
        block: "Block: $4.50 (2h5m left, $1.75/h)"
        daily: "Today: $8.25"
      }
    } else {
      {
        sess: ""
        block: ""
        daily: ""
      }
    }
    assert equal $result.run.exit_code 0 $"($case.name): ($result.run.stderr)"
    let expected_flock = [
      (expected-flock-call $result.cache_dir $result.config $CCUSAGE_SPEC.lock_name "ccusage")
    ]
    assert equal $result.flock_calls $expected_flock $"($case.name): lock attempt"
    assert equal $result.calls [] $"($case.name): ccusage calls"
    assert equal $result.fields $expected_fields $"($case.name): statusline fields"
    assert ($result.ccusage_lock | path exists) $"($case.name): persistent lock file"
  }
}

def "test held lock without cache renders no usage" [] {
  let dir = (mktemp --directory)

  let result = (invoke-statusline $dir --lock-held)
  assert equal $result.run.exit_code 0 $result.run.stderr

  assert equal $result.flock_calls [
    (expected-flock-call $result.cache_dir $result.config $CCUSAGE_SPEC.lock_name "ccusage")
  ]
  assert equal $result.calls []
  assert equal $result.fields {
    sess: ""
    block: ""
    daily: ""
  }
  assert ($result.ccusage_lock | path exists)
}

def "test http cost source skips blocks, queries endpoint, and renders combined Today" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let utc_date = (date now | date to-timezone "UTC" | format date "%Y-%m-%d")
  let base_url = $"($API_BASE_URL)/anthropic"

  let first = (invoke-statusline $dir --base-url $base_url)
  assert equal $first.run.exit_code 0 $first.run.stderr
  assert equal $first.fields {
    sess: ""
    block: ""
    daily: ""
  }
  assert equal $first.flock_calls [
    (expected-flock-call $first.cache_dir $first.config $DAILY_SPEC.lock_name "ccusage-daily")
    (expected-flock-call $first.cache_dir $first.config $BILLING_SPEC.lock_name "source:billing")
  ]
  assert equal $first.calls [(daily-call $today)]
  let expected_url = (
    $"($BILLING_URL)"
    + $"?start=($utc_date)T00%3A00%3A00Z&end=($utc_date)T23%3A59%3A59Z&scope=user"
  )
  assert equal $first.curl_calls [
    {
      args: [
        $expected_url
        "--fail"
        "--silent"
        "--show-error"
        "--location"
        "--connect-timeout" "5"
        "--max-time" "5"
        "--noproxy" "*"
        "--cacert" $first.ca_file
        "--variable" $"token@($first.token_file)"
        "--expand-header" "Authorization: Bearer {{token:trim}}"
      ]
      lock_exists: true
    }
  ]
  assert equal (open $first.daily_cache) (refreshed-daily $today)
  assert equal (open $first.remote_cache) (refreshed-remote $today)

  let second = (invoke-statusline $dir --base-url $base_url)
  assert equal $second.run.exit_code 0 $second.run.stderr
  assert equal $second.fields {
    sess: ""
    block: ""
    daily: "Today: $40.75 / $198.11"
  }
}

def "test http cost source supports header-file and bearer-env auth" [] {
  let base_url = $"($API_BASE_URL)/anthropic"

  let header_dir = (mktemp --directory)
  let header_res = (invoke-statusline $header_dir --base-url $base_url --auth-type "header_file")
  assert equal $header_res.run.exit_code 0 $header_res.run.stderr
  let header_args = $header_res.curl_calls.0.args
  assert ("--expand-header" in $header_args)
  assert ("X-API-Key: {{token:trim}}" in $header_args)

  let env_dir = (mktemp --directory)
  let env_res = (invoke-statusline $env_dir --base-url $base_url --auth-type "bearer_env")
  assert equal $env_res.run.exit_code 0 $env_res.run.stderr
  let env_args = $env_res.curl_calls.0.args
  assert ("%BILLING_API_TOKEN" in $env_args)
  assert ("Authorization: Bearer {{BILLING_API_TOKEN:trim}}" in $env_args)
}

def "test http cost source stale caches serve stale values while refreshing both" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let daily_cache = ($cache_dir | path join $DAILY_SPEC.cache_name)
  let remote_cache = ($cache_dir | path join $BILLING_SPEC.cache_name)
  (cached-daily $today) | save $daily_cache
  (cached-remote $today) | save $remote_cache
  touch -d "5 minutes ago" $daily_cache
  touch -d "5 minutes ago" $remote_cache

  let result = (invoke-statusline $dir --base-url $"($API_BASE_URL)/anthropic")
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.fields {
    sess: ""
    block: ""
    daily: "Today: $8.25 / $50.00"
  }
  assert equal (open $daily_cache) (refreshed-daily $today)
  assert equal (open $remote_cache) (refreshed-remote $today)
}

def "test http cost source converts non-UTC local calendar day to UTC window" [] {
  let dir = (mktemp --directory)
  let result = (
    invoke-statusline $dir
      --base-url $"($API_BASE_URL)/anthropic"
      --tz "UTC-8"
      --no-ca
  )
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal ($result.curl_calls | length) 1
  let curl_args = $result.curl_calls.0.args
  assert ($curl_args.0 | str contains "T16%3A00%3A00Z&end=")
  assert ($curl_args.0 | str ends-with "T15%3A59%3A59Z&scope=user")
  assert not ("--cacert" in $curl_args)
}

def "test http cost source skips query when token file is missing or empty" [] {
  for case in [
    {
      name: "missing token"
      no_token: true
      token_content: ""
    }
    {
      name: "empty token"
      no_token: false
      token_content: "   \n"
    }
  ] {
    let dir = (mktemp --directory)
    let today = (utc-today)
    let base_url = $"($API_BASE_URL)/anthropic"

    let first = (
      invoke-statusline $dir
        --base-url $base_url
        --no-token=$case.no_token
        --token-content $case.token_content
    )
    assert equal $first.run.exit_code 0 $"($case.name): ($first.run.stderr)"
    assert equal $first.curl_calls [] $"($case.name): no curl call"
    assert equal $first.calls [(daily-call $today)] $"($case.name): daily only"
    assert equal $first.flock_calls [
      (expected-flock-call $first.cache_dir $first.config $DAILY_SPEC.lock_name "ccusage-daily")
    ] $"($case.name): only daily flock"

    let second = (
      invoke-statusline $dir
        --base-url $base_url
        --no-token=$case.no_token
        --token-content $case.token_content
    )
    assert equal $second.fields {
      sess: ""
      block: ""
      daily: "Today: $40.75"
    } $"($case.name): local-only Today"
  }
}

def "test http fallback renders single Today value when only one source succeeds" [] {
  let dir_local_only = (mktemp --directory)
  let base_url = $"($API_BASE_URL)/anthropic"
  invoke-statusline $dir_local_only --base-url $base_url --curl-mode "fail" | ignore
  let local_only = (invoke-statusline $dir_local_only --base-url $base_url --curl-mode "fail")
  assert equal $local_only.fields {
    sess: ""
    block: ""
    daily: "Today: $40.75"
  }

  let dir_remote_only = (mktemp --directory)
  invoke-statusline $dir_remote_only --base-url $base_url --ccusage-mode "fail-daily" | ignore
  let remote_only = (
    invoke-statusline $dir_remote_only --base-url $base_url --ccusage-mode "fail-daily"
  )
  assert equal $remote_only.fields {
    sess: ""
    block: ""
    daily: "Today: $198.11"
  }
}

def "test non-matching base URL stays in default local mode" [] {
  let dir = (mktemp --directory)
  let today = (utc-today)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  (cached-usage $today) | save ($cache_dir | path join $CCUSAGE_SPEC.cache_name)

  let result = (invoke-statusline $dir --base-url $"($API_BASE_URL).evil.test/anthropic")
  assert equal $result.run.exit_code 0 $result.run.stderr
  assert equal $result.curl_calls []
  assert equal $result.fields {
    sess: ""
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
}

def "test command cost source parses plain float and JSON extract" [] {
  let dir_float = (mktemp --directory)
  let extra_float = {
    local: {
      provider: "none"
      show_block: false
    }
    cost_sources: [
      {
        id: "cmd-float"
        match: {
          env_exists: ["CMD_ENABLED"]
        }
        source: {
          type: "command"
          argv: ["bash" "-c" 'printf "12.34\n"']
        }
      }
    ]
  }
  with-env {CMD_ENABLED: "1"} {
    invoke-statusline $dir_float --extra-config $extra_float | ignore
    let rendered = (invoke-statusline $dir_float --extra-config $extra_float)
    assert equal $rendered.run.exit_code 0 $rendered.run.stderr
    assert equal $rendered.fields {
      sess: ""
      block: ""
      daily: "Today: $12.34"
    }
  }

  let dir_json = (mktemp --directory)
  let extra_json = {
    local: {
      provider: "none"
      show_block: false
    }
    cost_sources: [
      {
        id: "cmd-json"
        match: {}
        source: {
          type: "command"
          argv: ["bash" "-c" 'printf "{\"day\":\"%s\",\"cost\":{\"usd\":55.5}}\n" "$1"' "_" "{date}"]
          extract: ["cost" "usd"]
        }
      }
    ]
  }
  invoke-statusline $dir_json --extra-config $extra_json | ignore
  let rendered_json = (invoke-statusline $dir_json --extra-config $extra_json)
  assert equal $rendered_json.run.exit_code 0 $rendered_json.run.stderr
  assert equal $rendered_json.fields {
    sess: ""
    block: ""
    daily: "Today: $55.50"
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
    sess: ""
    block: "Block: $4.50 (2h5m left, $1.75/h)"
    daily: "Today: $8.25"
  }
}

def "test source-cache-spec sanitizes source ids" [] {
  let spec = (source-cache-spec "team/billing:v1")
  assert equal $spec.cache_name "statusline-source-team_billing_v1.json"
  assert equal $spec.lock_name "statusline-source-team_billing_v1.lock"
  assert equal $spec.refresh "source:team/billing:v1"
}
