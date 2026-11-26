# ==================================================================================================
# HTTP Cost Provider
# ==================================================================================================

use ../time.nu [duration-seconds local-day-window parse-duration render-template template-vars]
use ./common.nu [extract-cost non-empty-file parse-json-record]

export def auth-ready [auth: record, env_vars: record]: nothing -> bool {
  let kind = ($auth.type? | default "none")
  match $kind {
    "none" => true
    "bearer_file" => { non-empty-file ($auth.path? | default "") }
    "header_file" => {
      ($auth.header? | default "" | is-not-empty) and (non-empty-file ($auth.path? | default ""))
    }
    "bearer_env" => {
      let var = ($auth.env? | default "")
      ($var | is-not-empty) and (
        $env_vars | get -o $var | default "" | into string | str trim | is-not-empty
      )
    }
    _ => false
  }
}

def auth-curl-args [auth: record, env_vars: record]: nothing -> list<string> {
  let kind = ($auth.type? | default "none")
  match $kind {
    "none" => []
    "bearer_file" => {
      let path = ($auth.path? | default "")
      if not (non-empty-file $path) {
        error make {msg: "http cost source token file is missing or empty"}
      }
      [
        "--variable" $"token@($path)"
        "--expand-header" "Authorization: Bearer {{token:trim}}"
      ]
    }
    "header_file" => {
      let path = ($auth.path? | default "")
      let header = ($auth.header? | default "")
      if ($header | is-empty) or not (non-empty-file $path) {
        error make {msg: "http cost source header auth configuration is incomplete"}
      }
      [
        "--variable" $"token@($path)"
        "--expand-header" $"($header): {{token:trim}}"
      ]
    }
    "bearer_env" => {
      let var = ($auth.env? | default "")
      let value = ($env_vars | get -o $var | default "" | into string | str trim)
      if ($var | is-empty) or ($value | is-empty) {
        error make {msg: "http cost source bearer env variable is missing or empty"}
      }
      [
        "--variable" $"%($var)"
        "--expand-header" $"Authorization: Bearer {{($var):trim}}"
      ]
    }
    _ => {
      error make {msg: $"unsupported http auth type: ($kind)"}
    }
  }
}

export def build-query-url [base_url: string, query: record, vars: record]: nothing -> string {
  let rendered_base = (render-template $base_url $vars)
  if ($query | is-empty) {
    return $rendered_base
  }
  let encoded = (
    $query
    | transpose key value
    | reduce --fold {} {|entry, acc|
      $acc | insert $entry.key (render-template ($entry.value | into string) $vars)
    }
    | url build-query
  )
  let sep = if ($rendered_base | str contains "?") { "&" } else { "?" }
  $"($rendered_base)($sep)($encoded)"
}

export def fetch-http [
  source_cfg: record
  default_timeout: duration
  env_vars: record
  label: string = "http cost source"
]: nothing -> record {
  let raw_url = ($source_cfg.url? | default "")
  if ($raw_url | is-empty) {
    error make {msg: $"($label) url is empty"}
  }

  let window = (local-day-window)
  let vars = (template-vars $window)
  let url = (build-query-url $raw_url ($source_cfg.query? | default {}) $vars)

  let method = ($source_cfg.method? | default "GET" | str uppercase)
  let method_args = if $method != "GET" { ["--request" $method] } else { [] }

  let timeout_secs = (
    parse-duration ($source_cfg.timeout?) $default_timeout
    | duration-seconds $in
    | into string
  )
  let noproxy_args = if ($source_cfg.no_proxy? | default false) {
    ["--noproxy" "*"]
  } else {
    []
  }
  let ca_file = ($source_cfg.ca_file? | default "")
  let cacert_args = if ($ca_file | is-not-empty) and ($ca_file | path exists) {
    ["--cacert" $ca_file]
  } else {
    []
  }
  let header_args = (
    $source_cfg.headers?
    | default {}
    | transpose key value
    | each {|entry|
      let rendered = (render-template ($entry.value | into string) $vars)
      ["--header" $"($entry.key): ($rendered)"]
    }
    | flatten
  )
  let auth_args = (auth-curl-args ($source_cfg.auth? | default {}) $env_vars)

  let result = (
    ^curl $url
      --fail
      --silent
      --show-error
      --connect-timeout $timeout_secs
      --max-time $timeout_secs
      ...$method_args
      ...$noproxy_args
      ...$cacert_args
      ...$header_args
      ...$auth_args
    | complete
  )
  if $result.exit_code != 0 {
    error make {msg: $"($label) query exited ($result.exit_code)"}
  }

  let parsed = (parse-json-record $result.stdout $label)
  let cost = (extract-cost $parsed ($source_cfg.extract? | default []) $label)

  {
    date: $window.date
    has_cost: true
    daily_cost: $cost
  }
}
