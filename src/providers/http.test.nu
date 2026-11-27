#!/usr/bin/env nu

# ==================================================================================================
# HTTP Cost Provider Tests
# ==================================================================================================

use std/assert
use ./http.nu [auth-ready build-query-url fetch-http]
use ./providers.testlib.nu [install-stub read-calls]

const CURL_STUB = path self "../curl.stub.nu"

def "test auth-ready validates none, file, env, and unknown auth configs" [] {
  let dir = (mktemp --directory)
  let token = ($dir | path join "token")
  "tok" | save --force --raw $token
  let blank = ($dir | path join "blank")
  "  \n" | save --force --raw $blank

  let cases = [
    {
      name: "empty auth defaults to none"
      auth: {}
      env: {}
      expected: true
    }
    {
      name: "explicit none auth"
      auth: {type: "none"}
      env: {}
      expected: true
    }
    {
      name: "bearer_file with non-empty token"
      auth: {
        type: "bearer_file"
        path: $token
      }
      env: {}
      expected: true
    }
    {
      name: "bearer_file with blank token"
      auth: {
        type: "bearer_file"
        path: $blank
      }
      env: {}
      expected: false
    }
    {
      name: "header_file with header and token"
      auth: {
        type: "header_file"
        header: "X-API-Key"
        path: $token
      }
      env: {}
      expected: true
    }
    {
      name: "header_file with empty header"
      auth: {
        type: "header_file"
        header: ""
        path: $token
      }
      env: {}
      expected: false
    }
    {
      name: "bearer_env with populated variable"
      auth: {
        type: "bearer_env"
        env: "API_TOK"
      }
      env: {API_TOK: "secret"}
      expected: true
    }
    {
      name: "bearer_env with blank variable"
      auth: {
        type: "bearer_env"
        env: "API_TOK"
      }
      env: {API_TOK: "  "}
      expected: false
    }
    {
      name: "unsupported auth type"
      auth: {type: "unsupported"}
      env: {}
      expected: false
    }
  ]
  for case in $cases {
    assert equal (auth-ready $case.auth $case.env) $case.expected $case.name
  }
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
  assert ("-fsS" in $first_args)
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

  let url_err = try {
    fetch-http {} 5sec {} "billing"
    ""
  } catch {|e|
    $e.msg
  }
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
  } catch {|e|
    $e.msg
  }
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
      } catch {|e|
        $e.msg
      }
    }
    assert equal $err $case.expected
  }
}
