# ==================================================================================================
# Time, Duration, and Template Helpers
# ==================================================================================================

# Normalize shorthand units (`60s`, `15m`, `1h`) to Nushell duration syntax (`60sec`, `15min`, `1hr`).
export def parse-duration [value: any, fallback: duration]: nothing -> duration {
  if $value == null {
    return $fallback
  }
  let kind = ($value | describe)
  if $kind == "duration" {
    return $value
  }
  if $kind == "int" or $kind == "float" {
    return (try {
      $"($value)sec" | into duration
    } catch {
      $fallback
    })
  }
  if $kind != "string" {
    return $fallback
  }

  let normalized = (
    $value
    | str trim
    | str replace --regex '(\d+)s$' '${1}sec'
    | str replace --regex '(\d+)m$' '${1}min'
    | str replace --regex '(\d+)h$' '${1}hr'
  )
  try {
    $normalized | into duration
  } catch {
    $fallback
  }
}

export def duration-seconds [dur: duration]: nothing -> int {
  let secs = ($dur / 1sec | math round | into int)
  if $secs < 1 {
    1
  } else {
    $secs
  }
}

export def local-day-window []: nothing -> record {
  let now = (date now)
  let date_key = ($now | format date "%Y%m%d")
  let local_date = ($now | format date "%Y-%m-%d")
  let offset = ($now | format date "%z")
  let start_dt = ($"($local_date)T00:00:00($offset)" | into datetime)
  let end_dt = ($"($local_date)T23:59:59($offset)" | into datetime)

  {
    date: $date_key
    local_date: $local_date
    start_utc: ($start_dt | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ")
    end_utc: ($end_dt | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ")
    start_unix: ($start_dt | format date "%s" | into int)
    end_unix: ($end_dt | format date "%s" | into int)
  }
}

export def template-vars [window: record]: nothing -> record {
  {
    start_utc: $window.start_utc
    end_utc: $window.end_utc
    date: $window.local_date
    date_compact: $window.date
    start_unix: ($window.start_unix | into string)
    end_unix: ($window.end_unix | into string)
  }
}

export def render-template [template: string, vars: record]: nothing -> string {
  $vars
  | transpose key value
  | reduce --fold $template {|entry, acc|
    $acc | str replace --all $'{($entry.key)}' ($entry.value | into string)
  }
}
