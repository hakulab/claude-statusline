# ==================================================================================================
# Context Usage Segment
# ==================================================================================================

use ../format.nu [labeled]

export def format-context [input: record]: nothing -> string {
  let usage = ($input.context_window?.current_usage? | default {})
  let used = (
    ["input_tokens" "cache_creation_input_tokens" "cache_read_input_tokens"]
    | each {|key| $usage | get -o $key | default 0 }
    | math sum
  )
  let size = ($input.context_window?.context_window_size? | default 0)

  if $size == 0 {
    labeled "Ctx" "0%"
  } else {
    let percent = ($used * 100 // $size)
    let color = if $percent >= 80 {
      "red"
    } else if $percent >= 50 {
      "yellow"
    } else {
      "green"
    }
    labeled "Ctx" $"($percent)% \(($used // 1000)k/($size // 1000)k)" $color
  }
}
