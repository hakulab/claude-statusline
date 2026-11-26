#!/usr/bin/env nu

# ==================================================================================================
# Shared Stale-While-Revalidate Cache Tests
# ==================================================================================================

use std/assert
use ./cache.nu [cache-valid read-cache read-cached write-cache]

const TEST_SPEC = {
  cache_name: "statusline-test.json"
  lock_name: "statusline-test.lock"
  refresh: "ccusage"
  fields: [
    "date"
    "value"
  ]
}

def today-key []: nothing -> string {
  date now | format date "%Y%m%d"
}

def valid-entry []: nothing -> record {
  {
    date: (today-key)
    value: 42
  }
}

# --------------------------------------------------------------------------------------------------
# Validation and Reading
# --------------------------------------------------------------------------------------------------

def "test cache-valid accepts today records and rejects invalid shapes or dates" [] {
  assert (cache-valid (valid-entry) $TEST_SPEC.fields)
  assert not (cache-valid {date: (today-key)} $TEST_SPEC.fields)
  assert not (cache-valid {date: "20000101", value: 42} $TEST_SPEC.fields)
  assert not (cache-valid "not-a-record" $TEST_SPEC.fields)
}

def "test read-cache returns fresh data and empty record on missing, expired, or corrupt files" [] {
  let dir = (mktemp --directory)
  let cache = ($dir | path join $TEST_SPEC.cache_name)

  assert equal (read-cache $cache $TEST_SPEC.fields 60sec) {}

  let payload = (valid-entry)
  $payload | to json | save --force --raw $cache
  assert equal (read-cache $cache $TEST_SPEC.fields 60sec) $payload

  touch -d "5 minutes ago" $cache
  assert equal (read-cache $cache $TEST_SPEC.fields 60sec) {}
  assert equal (read-cache $cache $TEST_SPEC.fields 15min) $payload

  "{truncated" | save --force --raw $cache
  assert equal (read-cache $cache $TEST_SPEC.fields 60sec) {}
}

# --------------------------------------------------------------------------------------------------
# Atomic Write and Publication
# --------------------------------------------------------------------------------------------------

def "test write-cache publishes JSON atomically without temporary files" [] {
  let dir = (mktemp --directory)
  let cache = ($dir | path join $TEST_SPEC.cache_name)
  let payload = (valid-entry)

  write-cache $cache $payload

  assert equal (open $cache) $payload
  assert equal (ls $dir | where ($it.name | str ends-with ".tmp")) []
}

def "test write-cache reports save failure without temporary files" [] {
  let dir = (mktemp --directory)
  let blocked_parent = ($dir | path join "not-a-directory")
  touch $blocked_parent
  let cache = ($blocked_parent | path join $TEST_SPEC.cache_name)

  let err = try {
    write-cache $cache (valid-entry)
    ""
  } catch {|e| $e.msg }

  assert equal $err "failed to write usage cache"
  assert equal (ls $dir | get name) [$blocked_parent]
}

def "test write-cache preserves original file and cleans tmp when mv fails" [] {
  let dir = (mktemp --directory)
  let cache = ($dir | path join $TEST_SPEC.cache_name)
  let original = {
    date: (today-key)
    value: 1
  }
  $original | to json | save --force --raw $cache

  let err = with-env {
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    STUB_MV_FAIL: "1"
  } {
    try {
      write-cache $cache (valid-entry)
      ""
    } catch {|e| $e.msg }
  }

  assert equal $err "failed to publish usage cache"
  assert equal (open $cache) $original
  assert equal (ls $dir | where ($it.name | str ends-with ".tmp")) []
}

# --------------------------------------------------------------------------------------------------
# Stale-While-Revalidate and Lock Fallback
# --------------------------------------------------------------------------------------------------

def "test read-cached returns fresh cache without invoking flock" [] {
  let dir = (mktemp --directory)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let flock_log = ($dir | path join "flock.jsonl")
  let payload = (valid-entry)
  $payload | to json | save --force --raw ($cache_dir | path join $TEST_SPEC.cache_name)

  let got = with-env {
    FLOCK_LOG: $flock_log
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
  } {
    read-cached $cache_dir $TEST_SPEC "/unused.nu" "" 60sec 15min --sync-refresh
  }

  assert equal $got $payload
  assert not ($flock_log | path exists)
}

def "test read-cached serves stale data and triggers refresh when TTL expired" [] {
  let dir = (mktemp --directory)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $TEST_SPEC.cache_name)
  let flock_log = ($dir | path join "flock.jsonl")
  let payload = (valid-entry)
  $payload | to json | save --force --raw $cache
  touch -d "5 minutes ago" $cache

  let got = with-env {
    FLOCK_LOG: $flock_log
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    STUB_FLOCK_HELD: "1"
  } {
    read-cached $cache_dir $TEST_SPEC "/script.nu" "/cfg.toml" 60sec 15min --sync-refresh
  }

  assert equal $got $payload
  let calls = (open $flock_log | from json --objects)
  assert equal ($calls | length) 1
  assert equal $calls.0.lock ($cache_dir | path join $TEST_SPEC.lock_name)
  assert ($cache_dir | path join $TEST_SPEC.lock_name | path exists)
}

def "test read-cached returns empty when cache exceeds max-stale" [] {
  let dir = (mktemp --directory)
  let cache_dir = ($dir | path join "cache")
  mkdir $cache_dir
  let cache = ($cache_dir | path join $TEST_SPEC.cache_name)
  let flock_log = ($dir | path join "flock.jsonl")
  (valid-entry) | to json | save --force --raw $cache
  touch -d "20 minutes ago" $cache

  let got = with-env {
    FLOCK_LOG: $flock_log
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    STUB_FLOCK_HELD: "1"
  } {
    read-cached $cache_dir $TEST_SPEC "/script.nu" "" 60sec 15min --sync-refresh
  }

  assert equal $got {}
  assert equal (open $flock_log | from json --objects | length) 1
}
