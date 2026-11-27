# ==================================================================================================
# Terminal Formatting Helpers
# ==================================================================================================

export def paint [text: string, style: string]: nothing -> string {
  if ($style | is-empty) {
    $text
  } else {
    $"($style)($text)(ansi reset)"
  }
}

export def labeled [
  label: string
  value: string
  value_style: string
  label_style: string
]: nothing -> string {
  $"(paint $"($label):" $label_style) (paint $value $value_style)"
}

export def usd [amount: float]: nothing -> string {
  if $amount == 0 {
    "$0.00"
  } else {
    $"$($amount | into string --decimals 2)"
  }
}
