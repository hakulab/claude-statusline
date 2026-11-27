#!/usr/bin/env nu

# ==================================================================================================
# Shared Cost Provider Helper Tests
# ==================================================================================================

use std/assert
use ./common.nu [extract-cost non-empty-file parse-json-record source-cache-spec]

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
