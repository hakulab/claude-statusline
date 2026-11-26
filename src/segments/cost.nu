# ==================================================================================================
# Usage and Cost Segments
# ==================================================================================================

use ../format.nu [labeled paint usd]

export def format-remaining [minutes: int]: nothing -> string {
  if $minutes <= 0 {
    return ""
  }
  let hours = ($minutes // 60)
  if $hours > 0 {
    $"($hours)h($minutes mod 60)m left"
  } else {
    $"($minutes)m left"
  }
}

export def format-block [data: record]: nothing -> string {
  if not ($data.has_block? | default false) {
    return ""
  }

  let remaining = ($data.remaining_minutes? | default 0)
  let burn_rate = ($data.burn_rate? | default 0.0)
  let details = (
    [
      (format-remaining $remaining)
      (if $burn_rate > 0 { $"(usd $burn_rate)/h" })
    ]
    | compact --empty
    | str join ", "
  )
  let suffix = if ($details | is-empty) {
    ""
  } else {
    $" (paint $"\(($details)\)" "yellow")"
  }

  $"(labeled "Block" (usd ($data.block_cost? | default 0.0)) "cyan")($suffix)"
}

export def format-session [input: record]: nothing -> string {
  let raw = $input.cost?.total_cost_usd?
  if $raw == null {
    return ""
  }
  let amount = (try { $raw | into float } catch { null })
  if $amount == null {
    ""
  } else {
    labeled "Sess" (usd $amount) "cyan"
  }
}

export def format-today [local: record, remotes: list<record>]: nothing -> string {
  let local_value = if ($local.has_daily? | default false) {
    usd ($local.daily_cost? | default 0.0)
  }
  let remote_values = (
    $remotes
    | each {|remote|
      if ($remote.has_cost? | default false) {
        usd ($remote.daily_cost? | default 0.0)
      }
    }
  )
  let values = ([$local_value ...$remote_values] | compact --empty)
  if ($values | is-empty) {
    ""
  } else {
    labeled "Today" ($values | str join " / ") "cyan"
  }
}
