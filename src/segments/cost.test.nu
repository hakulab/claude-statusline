#!/usr/bin/env nu

# ==================================================================================================
# Cost Segment Formatting Tests
# ==================================================================================================

use std/assert
use ./cost.nu [format-block format-remaining format-session format-today]

def "test format-session formats cost, zero, and omits missing or invalid values" [] {
  assert equal (format-session {cost: {total_cost_usd: 1.234}} | ansi strip) "Sess: $1.23"
  assert equal (format-session {cost: {total_cost_usd: 0}} | ansi strip) "Sess: $0.00"
  assert equal (format-session {}) ""
  assert equal (format-session {cost: {total_cost_usd: "bad"}}) ""
}

def "test format-remaining and format-block format active and inactive blocks" [] {
  assert equal (format-remaining 45) "45m left"
  assert equal (format-remaining 125) "2h5m left"
  assert equal (format-remaining 0) ""

  let full_block = {
    has_block: true
    block_cost: 4.5
    remaining_minutes: 125
    burn_rate: 1.75
  }
  assert equal (format-block $full_block | ansi strip) "Block: $4.50 (2h5m left, $1.75/h)"

  let bare_block = {
    has_block: true
    block_cost: 2.0
    remaining_minutes: 0
    burn_rate: 0.0
  }
  assert equal (format-block $bare_block | ansi strip) "Block: $2.00"
  assert equal (format-block {has_block: false}) ""
}

def "test format-today renders combined, single-side, and empty values" [] {
  let local = {
    has_daily: true
    daily_cost: 40.75
  }
  let remote_a = {
    has_cost: true
    daily_cost: 198.11
  }
  let remote_b = {
    has_cost: true
    daily_cost: 12.5
  }
  let cases = [
    {
      name: "local and single remote"
      local: $local
      remotes: [$remote_a]
      expected: "Today: $40.75 / $198.11"
    }
    {
      name: "local and multiple remotes"
      local: $local
      remotes: [$remote_a $remote_b]
      expected: "Today: $40.75 / $198.11 / $12.50"
    }
    {
      name: "local only"
      local: $local
      remotes: []
      expected: "Today: $40.75"
    }
    {
      name: "remote only"
      local: {}
      remotes: [$remote_a]
      expected: "Today: $198.11"
    }
    {
      name: "empty local and remote"
      local: {}
      remotes: []
      expected: ""
    }
  ]
  for case in $cases {
    let rendered = (format-today $case.local $case.remotes)
    let actual = if $case.expected == "" { $rendered } else { $rendered | ansi strip }
    assert equal $actual $case.expected $case.name
  }
}
