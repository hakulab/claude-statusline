#!/usr/bin/env nu

# ==================================================================================================
# Cost Provider Tests
# ==================================================================================================

use std/assert
use ./ccusage.nu [ccusage-json current-ccusage]
use ./command.nu [fetch-command]
use ./common.nu [extract-cost non-empty-file parse-json-record source-cache-spec]
use ./http.nu [auth-ready build-query-url fetch-http]

const CCUSAGE_STUB = path self "../ccusage.stub.nu"
const CURL_STUB = path self "../curl.stub.nu"

def install-stub [src: path, dir: path, name: string]: nothing -> nothing {
  let target = ($dir | path join $name)
  let script = (open --raw $src | into string | str replace --regex '^#![^\r\n]*(\r?\n)?' "")
  $"#!($nu.current-exe) --no-config-file\n($script)" | save --force $target
  ^chmod +x $target
}

def read-calls [log: path]: nothing -> list<record> {
  if ($log | path exists) {
    open $log | from json --objects
  } else {
    []
  }
}

# --------------------------------------------------------------------------------------------------
# Common Helpers
# --------------------------------------------------------------------------------------------------

def "test source-cache-spec sanitizes source ids" [] {
  let spec = (source-cache-spec "team/billing:v1")
  assert equal $spec {
    cache_name: "statusline-source-team_billing_v1.json"
    lock_name: "statusline-source-team_billing_v1.lock"
    refresh: "source:team/billing:v1"
    fields: [
      "date"
      "has_cost"
      "daily_cost"
    ]
  }
}

def "test non-empty-file distinguishes populated, blank, and missing files" [] {
  let dir = (mktemp --directory)
  let filled = ($dir | path join "token")
  "secret\n" | save --force --raw $filled
  let blank = ($dir | path join "blank")
  "   \n" | save --force --raw $blank

  assert (non-empty-file $filled)
  assert not (non-empty-file $blank)
  assert not (non-empty-file ($dir | path join "missing"))
  assert not (non-empty-file "")
}

def "test parse-json-record accepts objects and rejects invalid or scalar JSON" [] {
  assert equal (parse-json-record '{"a": 1}' "probe") {a: 1}

  for bad in ["not-json" "42" "[1, 2]"] {
    let err = try {
      parse-json-record $bad "probe"
      ""
    } catch {|e| $e.msg }
    assert equal $err "probe returned invalid JSON"
  }
}

def "test extract-cost resolves nested floats and rejects missing, bool, or non-finite fields" [] {
  let payload = {
    usage: {
      total_usd: 19.5
      label: "none"
      flag: true
      nan_val: "NaN"
      inf_val: "inf"
      neg_inf_val: "-inf"
    }
  }
  assert equal (extract-cost $payload ["usage" "total_usd"] "probe") 19.5

  let empty_err = try { extract-cost $payload [] "probe"; "" } catch {|e| $e.msg }
  assert equal $empty_err "probe extract path must not be empty"

  let missing_err = try { extract-cost $payload ["usage" "missing"] "probe"; "" } catch {|e| $e.msg }
  assert equal $missing_err "probe response missing usage.missing"

  for field in ["label" "flag" "nan_val" "inf_val" "neg_inf_val"] {
    let type_err = try { extract-cost $payload ["usage" $field] "probe"; "" } catch {|e| $e.msg }
    assert equal $type_err $"probe usage.($field) is not numeric"
  }
}

# --------------------------------------------------------------------------------------------------
# Local ccusage Provider
# --------------------------------------------------------------------------------------------------

def "test current-ccusage fetches daily only by default and adds blocks with flag" [] {
  let dir = (mktemp --directory)
  install-stub $CCUSAGE_STUB $dir "ccusage"
  let log = ($dir | path join "ccusage.jsonl")
  let today = (date now | format date "%Y%m%d")

  let daily = with-env {
    CCUSAGE_MODE: "success"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $log
  } {
    current-ccusage
  }
  assert equal $daily {
    date: $today
    has_daily: true
    daily_cost: 40.75
  }
  assert equal (read-calls $log | length) 1

  let full_log = ($dir | path join "ccusage-full.jsonl")
  let full = with-env {
    CCUSAGE_MODE: "success"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $full_log
  } {
    current-ccusage --with-blocks
  }
  assert equal $full {
    date: $today
    has_daily: true
    daily_cost: 40.75
    has_block: true
    block_cost: 12.5
    remaining_minutes: 185
    burn_rate: 3.25
  }
  assert equal (read-calls $full_log | length) 2
}

def "test ccusage-json reports nonzero exit and scalar JSON errors" [] {
  let dir = (mktemp --directory)
  install-stub $CCUSAGE_STUB $dir "ccusage"
  let log = ($dir | path join "ccusage.jsonl")

  let exit_err = with-env {
    CCUSAGE_MODE: "fail-blocks"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $log
  } {
    try { ccusage-json [blocks --active]; "" } catch {|e| $e.msg }
  }
  assert equal $exit_err "ccusage blocks --active exited 1"

  let scalar_err = with-env {
    CCUSAGE_MODE: "scalar-blocks"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $log
  } {
    try { ccusage-json [blocks --active]; "" } catch {|e| $e.msg }
  }
  assert equal $scalar_err "ccusage blocks --active returned invalid JSON"
}

# --------------------------------------------------------------------------------------------------
# HTTP Provider
# --------------------------------------------------------------------------------------------------

def "test auth-ready validates none, file, env, and unknown auth configs" [] {
  let dir = (mktemp --directory)
  let token = ($dir | path join "token")
  "tok" | save --force --raw $token
  let blank = ($dir | path join "blank")
  "  \n" | save --force --raw $blank

  assert (auth-ready {} {})
  assert (auth-ready {type: "none"} {})
  assert (auth-ready {type: "bearer_file", path: $token} {})
  assert not (auth-ready {type: "bearer_file", path: $blank} {})
  assert (auth-ready {type: "header_file", header: "X-API-Key", path: $token} {})
  assert not (auth-ready {type: "header_file", header: "", path: $token} {})
  assert (auth-ready {type: "bearer_env", env: "API_TOK"} {API_TOK: "secret"})
  assert not (auth-ready {type: "bearer_env", env: "API_TOK"} {API_TOK: "  "})
  assert not (auth-ready {type: "unsupported"} {})
}

def "test build-query-url renders templates and appends query strings" [] {
  let vars = {
    start_utc: "2026-11-26T00:00:00Z"
    end_utc: "2026-11-26T23:59:59Z"
    date: "2026-11-26"
  }
  let url1 = (
    build-query-url "https://billing.example.com/v1/{date}" {
      start: "{start_utc}"
      end: "{end_utc}"
    } $vars
  )
  assert equal $url1 (
    "https://billing.example.com/v1/2026-11-26"
    + "?start=2026-11-26T00%3A00%3A00Z&end=2026-11-26T23%3A59%3A59Z"
  )

  let url2 = (
    build-query-url "https://billing.example.com/v1/usage?scope=user" {day: "{date}"} $vars
  )
  assert equal $url2 "https://billing.example.com/v1/usage?scope=user&day=2026-11-26"
}

def "test fetch-http builds curl args for bearer-file, header-file, and bearer-env auth" [] {
  let dir = (mktemp --directory)
  install-stub $CURL_STUB $dir "curl"
  let token = ($dir | path join "token")
  "secret-token" | save --force --raw $token
  let ca = ($dir | path join "ca.crt")
  "ca" | save --force --raw $ca
  let log = ($dir | path join "curl.jsonl")

  let res = with-env {
    CURL_LOG: $log
    CURL_MODE: "success"
    PATH: ($env.PATH | prepend $dir)
  } {
    fetch-http {
      url: "https://billing.example.com/v1/usage"
      query: {day: "{date}"}
      headers: {Accept: "application/json"}
      auth: {
        type: "bearer_file"
        path: $token
      }
      ca_file: $ca
      no_proxy: true
      extract: ["usage" "total_usd"]
    } 5sec {} "billing"
  }
  assert equal $res.has_cost true
  assert equal $res.daily_cost 198.11

  let first_args = (read-calls $log | get 0.args)
  assert ("--location" not-in $first_args)
  assert ("--noproxy" in $first_args)
  assert ("--cacert" in $first_args)
  assert ("Accept: application/json" in $first_args)
  assert ($"token@($token)" in $first_args)
  assert ("Authorization: Bearer {{token:trim}}" in $first_args)

  let header_log = ($dir | path join "curl-header.jsonl")
  with-env {
    CURL_LOG: $header_log
    CURL_MODE: "success"
    PATH: ($env.PATH | prepend $dir)
  } {
    fetch-http {
      url: "https://billing.example.com/v1/usage"
      auth: {
        type: "header_file"
        header: "X-API-Key"
        path: $token
      }
      extract: ["usage" "total_usd"]
    } 5sec {} "billing"
  } | ignore
  assert ("X-API-Key: {{token:trim}}" in (read-calls $header_log | get 0.args))

  let env_log = ($dir | path join "curl-env.jsonl")
  with-env {
    CURL_LOG: $env_log
    CURL_MODE: "success"
    PATH: ($env.PATH | prepend $dir)
  } {
    fetch-http {
      url: "https://billing.example.com/v1/usage"
      auth: {
        type: "bearer_env"
        env: "BILLING_TOKEN"
      }
      extract: ["usage" "total_usd"]
    } 5sec {BILLING_TOKEN: "tok"} "billing"
  } | ignore
  let env_args = (read-calls $env_log | get 0.args)
  assert ("%BILLING_TOKEN" in $env_args)
  assert ("Authorization: Bearer {{BILLING_TOKEN:trim}}" in $env_args)
}

def "test fetch-http reports missing url, missing token, and curl or payload errors" [] {
  let dir = (mktemp --directory)
  install-stub $CURL_STUB $dir "curl"
  let log = ($dir | path join "curl.jsonl")

  let url_err = try { fetch-http {} 5sec {} "billing"; "" } catch {|e| $e.msg }
  assert equal $url_err "billing url is empty"

  let tok_err = try {
    fetch-http {
      url: "https://billing.example.com/v1/usage"
      auth: {
        type: "bearer_file"
        path: ($dir | path join "absent")
      }
      extract: ["usage" "total_usd"]
    } 5sec {} "billing"
    ""
  } catch {|e| $e.msg }
  assert equal $tok_err "http cost source token file is missing or empty"

  for case in [
    {
      mode: "fail"
      expected: "billing query exited 1"
    }
    {
      mode: "invalid-json"
      expected: "billing returned invalid JSON"
    }
    {
      mode: "missing-cost"
      expected: "billing response missing usage.total_usd"
    }
  ] {
    let err = with-env {
      CURL_LOG: $log
      CURL_MODE: $case.mode
      PATH: ($env.PATH | prepend $dir)
    } {
      try {
        fetch-http {
          url: "https://billing.example.com/v1/usage"
          extract: ["usage" "total_usd"]
        } 5sec {} "billing"
        ""
      } catch {|e| $e.msg }
    }
    assert equal $err $case.expected
  }
}

# --------------------------------------------------------------------------------------------------
# Command Provider
# --------------------------------------------------------------------------------------------------

def "test fetch-command parses plain float and JSON extract with templates" [] {
  let plain = (
    fetch-command {
      argv: ["bash" "-c" 'printf "12.34\n"']
    } 5sec "cmd-plain"
  )
  assert equal $plain.has_cost true
  assert equal $plain.daily_cost 12.34

  let extracted = (
    fetch-command {
      argv: ["bash" "-c" 'printf "{\"day\":\"%s\",\"cost\":{\"usd\":55.5}}\n" "$1"' "_" "{date}"]
      extract: ["cost" "usd"]
    } 5sec "cmd-json"
  )
  assert equal $extracted.has_cost true
  assert equal $extracted.daily_cost 55.5
}

def "test fetch-command reports empty argv, nonzero exit, and non-numeric stdout" [] {
  let empty_err = try { fetch-command {argv: []} 5sec "cmd"; "" } catch {|e| $e.msg }
  assert equal $empty_err "cmd argv must not be empty"

  let exit_err = try {
    fetch-command {argv: ["bash" "-c" "exit 3"]} 5sec "cmd"
    ""
  } catch {|e| $e.msg }
  assert equal $exit_err "cmd command exited 3"

  for bad in ["not-a-number" "NaN" "inf" "-inf"] {
    let num_err = try {
      fetch-command {argv: ["bash" "-c" 'printf "%s\n" "$1"' "_" $bad]} 5sec "cmd"
      ""
    } catch {|e| $e.msg }
    assert equal $num_err "cmd stdout is not numeric"
  }
}
