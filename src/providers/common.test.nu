#!/usr/bin/env nu

# ==================================================================================================
# Shared Cost Provider Helper Tests
# ==================================================================================================

use std/assert
use ./common.nu [extract-cost non-empty-file parse-json-record source-cache-spec]

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
    } catch {|e|
      $e.msg
    }
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

  let cases = [
    {
      path: []
      expected: "probe extract path must not be empty"
    }
    {
      path: ["usage" "missing"]
      expected: "probe response missing usage.missing"
    }
    {
      path: ["usage" "label"]
      expected: "probe usage.label is not numeric"
    }
    {
      path: ["usage" "flag"]
      expected: "probe usage.flag is not numeric"
    }
    {
      path: ["usage" "nan_val"]
      expected: "probe usage.nan_val is not numeric"
    }
    {
      path: ["usage" "inf_val"]
      expected: "probe usage.inf_val is not numeric"
    }
    {
      path: ["usage" "neg_inf_val"]
      expected: "probe usage.neg_inf_val is not numeric"
    }
  ]
  for case in $cases {
    let err = try {
      extract-cost $payload $case.path "probe"
      ""
    } catch {|e|
      $e.msg
    }
    assert equal $err $case.expected
  }
}

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
