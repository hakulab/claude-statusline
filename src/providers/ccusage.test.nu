#!/usr/bin/env nu

# ==================================================================================================
# Local ccusage Cost Provider Tests
# ==================================================================================================

use std/assert
use ./ccusage.nu [ccusage-json current-ccusage]
use ./providers.testlib.nu [install-stub read-calls]

const CCUSAGE_STUB = path self "../ccusage.stub.nu"

def "test ccusage-json reports nonzero exit and scalar JSON errors" [] {
  let dir = (mktemp --directory)
  install-stub $CCUSAGE_STUB $dir "ccusage"
  let log = ($dir | path join "ccusage.jsonl")

  let exit_err = with-env {
    CCUSAGE_MODE: "fail-blocks"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $log
  } {
    try {
      ccusage-json ["blocks" "--active"]
      ""
    } catch {|e|
      $e.msg
    }
  }
  assert equal $exit_err "ccusage blocks --active exited 1"

  let scalar_err = with-env {
    CCUSAGE_MODE: "scalar-blocks"
    PATH: ($env.PATH | prepend $dir)
    STUB_LOG: $log
  } {
    try {
      ccusage-json ["blocks" "--active"]
      ""
    } catch {|e|
      $e.msg
    }
  }
  assert equal $scalar_err "ccusage blocks --active returned invalid JSON"
}

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
