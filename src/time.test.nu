#!/usr/bin/env nu

# ==================================================================================================
# Time, Duration, and Template Helper Tests
# ==================================================================================================

use std/assert
use ./time.nu [
  duration-seconds
  local-day-window
  parse-duration
  render-template
  template-vars
]

# --------------------------------------------------------------------------------------------------
# Duration Parsing
# --------------------------------------------------------------------------------------------------

def "test parse-duration normalizes shorthand units" [] {
  assert equal (parse-duration "60s" 10sec) 60sec
  assert equal (parse-duration "15m" 10sec) 15min
  assert equal (parse-duration "2h" 10sec) 2hr
  assert equal (parse-duration " 45s " 10sec) 45sec
}

def "test parse-duration accepts native durations and numeric seconds" [] {
  assert equal (parse-duration 30sec 10sec) 30sec
  assert equal (parse-duration "30sec" 10sec) 30sec
  assert equal (parse-duration 45 10sec) 45sec
  assert equal (parse-duration 1.5 10sec) 1500ms
}

def "test parse-duration falls back on null, non-positive, invalid strings, and other types" [] {
  assert equal (parse-duration null 10sec) 10sec
  assert equal (parse-duration "invalid" 10sec) 10sec
  assert equal (parse-duration "" 10sec) 10sec
  assert equal (parse-duration [10] 10sec) 10sec
  assert equal (parse-duration 0 10sec) 10sec
  assert equal (parse-duration (-5) 10sec) 10sec
  assert equal (parse-duration "0s" 10sec) 10sec
  assert equal (parse-duration "-10s" 10sec) 10sec
  assert equal (parse-duration 0sec 10sec) 10sec
  assert equal (parse-duration (-5sec) 10sec) 10sec
}

def "test duration-seconds rounds and clamps to at least one second" [] {
  assert equal (duration-seconds 5sec) 5
  assert equal (duration-seconds 1min) 60
  assert equal (duration-seconds 200ms) 1
  assert equal (duration-seconds 0sec) 1
}

# --------------------------------------------------------------------------------------------------
# Local Day Window and Template Rendering
# --------------------------------------------------------------------------------------------------

def "test local-day-window and template-vars span one calendar day" [] {
  let window = (local-day-window)
  assert equal ($window.end_unix - $window.start_unix) 86399
  assert equal ($window.date | str length) 8
  assert equal ($window.local_date | str replace --all "-" "") $window.date

  let vars = (template-vars $window)
  assert equal $vars {
    start_utc: $window.start_utc
    end_utc: $window.end_utc
    date: $window.local_date
    date_compact: $window.date
    start_unix: ($window.start_unix | into string)
    end_unix: ($window.end_unix | into string)
  }
}

def "test render-template substitutes all placeholders and keeps unknown tokens" [] {
  let vars = {
    start_utc: "2026-11-26T00:00:00Z"
    end_utc: "2026-11-26T23:59:59Z"
    date: "2026-11-26"
    date_compact: "20261126"
    start_unix: "1795564800"
    end_unix: "1795651199"
  }
  let template = (
    "from={start_utc}&to={end_utc}&d={date}&c={date_compact}&s={start_unix}&e={end_unix}&x={other}"
  )
  let expected = (
    "from=2026-11-26T00:00:00Z&to=2026-11-26T23:59:59Z"
    + "&d=2026-11-26&c=20261126&s=1795564800&e=1795651199&x={other}"
  )
  assert equal (render-template $template $vars) $expected
}
