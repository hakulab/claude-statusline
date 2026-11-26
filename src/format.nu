# ==================================================================================================
# Terminal Formatting Helpers
# ==================================================================================================

export def dim [text: string]: nothing -> string {
  $"(ansi white_dimmed)($text)(ansi reset)"
}

export def paint [text: string, color: string]: nothing -> string {
  $"(ansi $color)($text)(ansi reset)"
}

export def labeled [label: string, value: string, color: string = "green"]: nothing -> string {
  $"(dim $"($label):") (paint $value $color)"
}

export def usd [amount: float]: nothing -> string {
  if $amount == 0 {
    "$0.00"
  } else {
    $"$($amount | into string --decimals 2)"
  }
}
