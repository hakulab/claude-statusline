#!/usr/bin/env nu

# ==================================================================================================
# curl Stub
# ==================================================================================================
# Records invocations and emits billing payloads or failures selected by CURL_MODE.
# ==================================================================================================

def --wrapped main [...args: string] {
  let lock = ($env.STUB_REMOTE_LOCK? | default "")
  let mode = ($env.CURL_MODE? | default "success")
  {
    args: $args
    lock_exists: (($lock | is-not-empty) and ($lock | path exists))
  }
  | to json --raw
  | $"($in)\n"
  | save --append $env.CURL_LOG

  match $mode {
    "fail" => {
      print --stderr "Injected HTTP provider failure"
      exit 1
    }
    "invalid-json" => {
      print "not-json"
    }
    "scalar" => {
      print "0"
    }
    "missing-cost" => {
      print ({usage: {}} | to json)
    }
    _ => {
      print ({usage: {total_usd: 198.11}} | to json)
    }
  }
}
