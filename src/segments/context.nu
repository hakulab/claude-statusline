# ==================================================================================================
# Context Usage Segment
# ==================================================================================================

use ../format.nu [labeled]
use ../theme.nu [default-theme]

export def format-context [input: record, --theme: record]: nothing -> string {
  let t = ($theme | default (default-theme))
  let usage = ($input.context_window?.current_usage? | default {})
  let used = (
    ["input_tokens" "cache_creation_input_tokens" "cache_read_input_tokens"]
    | each {|key| $usage | get -o $key | default 0 }
    | math sum
  )
  let size = ($input.context_window?.context_window_size? | default 0)

  if $size == 0 {
    labeled "Ctx" "0%" $t.success $t.muted
  } else {
    let percent = ($used * 100 // $size)
    let style = if $percent >= 80 {
      $t.error
    } else if $percent >= 50 {
      $t.warning
    } else {
      $t.success
    }
    labeled "Ctx" $"($percent)% \(($used // 1000)k/($size // 1000)k)" $style $t.muted
  }
}
