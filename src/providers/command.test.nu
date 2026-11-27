#!/usr/bin/env nu

# ==================================================================================================
# Command Cost Provider Tests
# ==================================================================================================

use std/assert
use ./command.nu [fetch-command]

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
      argv: ["printf" '{"day":"%s","cost":{"usd":55.5}}\n' "{date}"]
      extract: ["cost" "usd"]
    } 5sec "cmd-json"
  )
  assert equal $extracted.has_cost true
  assert equal $extracted.daily_cost 55.5
}

def "test fetch-command reports empty argv, nonzero exit, and non-numeric stdout" [] {
  let empty_err = try {
    fetch-command {argv: []} 5sec "cmd"
    ""
  } catch {|e|
    $e.msg
  }
  assert equal $empty_err "cmd argv must not be empty"

  let exit_err = try {
    fetch-command {argv: ["bash" "-c" "exit 3"]} 5sec "cmd"
    ""
  } catch {|e|
    $e.msg
  }
  assert equal $exit_err "cmd command exited 3"

  for bad in ["not-a-number" "NaN" "inf" "-inf"] {
    let num_err = try {
      fetch-command {argv: ["bash" "-c" 'printf "%s\n" "$1"' "_" $bad]} 5sec "cmd"
      ""
    } catch {|e|
      $e.msg
    }
    assert equal $num_err "cmd stdout is not numeric"
  }
}
