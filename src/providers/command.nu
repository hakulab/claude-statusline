# ==================================================================================================
# Command Cost Provider
# ==================================================================================================

use ../time.nu [duration-seconds local-day-window parse-duration render-template template-vars]
use ./common.nu [extract-cost parse-json-record]

export def fetch-command [
  source_cfg: record
  default_timeout: duration
  label: string = "command cost source"
]: nothing -> record {
  let raw_argv = ($source_cfg.argv? | default [])
  if ($raw_argv | is-empty) {
    error make {msg: $"($label) argv must not be empty"}
  }

  let window = (local-day-window)
  let vars = (template-vars $window)
  let argv = ($raw_argv | each {|arg| render-template ($arg | into string) $vars })
  let timeout_secs = (
    parse-duration ($source_cfg.timeout?) $default_timeout
    | duration-seconds $in
    | into string
  )

  let result = (^timeout $timeout_secs ...$argv | complete)
  if $result.exit_code != 0 {
    error make {msg: $"($label) command exited ($result.exit_code)"}
  }

  let extract = ($source_cfg.extract? | default [])
  let cost = if ($extract | is-empty) {
    try {
      $result.stdout | str trim | into float
    } catch {
      error make {msg: $"($label) stdout is not numeric"}
    }
  } else {
    let parsed = (parse-json-record $result.stdout $label)
    extract-cost $parsed $extract $label
  }

  {
    date: $window.date
    has_cost: true
    daily_cost: $cost
  }
}
