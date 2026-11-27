# ==================================================================================================
# Theme Presets, Color Parsing, and SGR Compilation
# ==================================================================================================

const ANSI_FG_CODES = {
  black: 30
  red: 31
  green: 32
  yellow: 33
  blue: 34
  magenta: 35
  purple: 35
  cyan: 36
  white: 37
  gray: 37
  grey: 37
  bright_black: 90
  dark_gray: 90
  dark_grey: 90
  bright_red: 91
  light_red: 91
  bright_green: 92
  light_green: 92
  bright_yellow: 93
  light_yellow: 93
  bright_blue: 94
  light_blue: 94
  bright_magenta: 95
  light_magenta: 95
  bright_purple: 95
  light_purple: 95
  bright_cyan: 96
  light_cyan: 96
  bright_white: 97
  light_white: 97
}

const SLOTS = [
  "accent"
  "info"
  "success"
  "warning"
  "error"
  "mode"
  "muted"
  "separator"
]

const MODIFIER_CODES = [
  [name code];
  ["bold" "1"]
  ["dim" "2"]
  ["italic" "3"]
  ["underlined" "4"]
  ["reversed" "7"]
]

const MODIFIER_NAMES = [
  "bold"
  "dim"
  "italic"
  "underlined"
  "reversed"
]

const EMPTY_STYLE = {
  fg: null
  bg: null
  bold: false
  dim: false
  italic: false
  underlined: false
  reversed: false
}

const EMPTY_THEME = {
  accent: ""
  info: ""
  success: ""
  warning: ""
  error: ""
  mode: ""
  muted: ""
  separator: ""
}

const PRESETS = {
  ansi: {
    accent: {
      fg: "blue"
      bold: true
    }
    info: {fg: "cyan"}
    success: {fg: "green"}
    warning: {fg: "yellow"}
    error: {fg: "red"}
    mode: {fg: "magenta"}
    muted: {dim: true}
    separator: {dim: true}
  }
  catppuccin-mocha: {
    accent: {
      fg: "#89b4fa"
      bold: true
    }
    info: {fg: "#94e2d5"}
    success: {fg: "#a6e3a1"}
    warning: {fg: "#f9e2af"}
    error: {fg: "#f38ba8"}
    mode: {fg: "#cba6f7"}
    muted: {fg: "#a6adc8"}
    separator: {fg: "#585b70"}
  }
  catppuccin-latte: {
    accent: {
      fg: "#1e66f5"
      bold: true
    }
    info: {fg: "#179299"}
    success: {fg: "#40a02b"}
    warning: {fg: "#df8e1d"}
    error: {fg: "#d20f39"}
    mode: {fg: "#8839ef"}
    muted: {fg: "#6c6f85"}
    separator: {fg: "#acb0be"}
  }
}

def parse-color [raw: string, channel: string]: nothing -> record {
  let norm = ($raw | str trim | str lowercase)
  if $norm == "reset" or $norm == "default" {
    return {
      ok: true
      sgr: null
    }
  }

  let ansi_fg = ($ANSI_FG_CODES | get -o $norm)
  if $ansi_fg != null {
    let code = if $channel == "bg" { $ansi_fg + 10 } else { $ansi_fg }
    return {
      ok: true
      sgr: ($code | into string)
    }
  }

  # 6-digit hex RGB (#RRGGBB).
  let hex = (
    $norm
    | parse --regex '^#(?<r>[0-9a-f]{2})(?<g>[0-9a-f]{2})(?<b>[0-9a-f]{2})$'
    | get -o 0
  )
  if $hex != null {
    let prefix = if $channel == "bg" { "48;2" } else { "38;2" }
    # Prefix with `0x` so byte `"0b"` is not parsed as a binary literal by `into int --radix 16`.
    let r = ($"0x($hex.r)" | into int)
    let g = ($"0x($hex.g)" | into int)
    let b = ($"0x($hex.b)" | into int)
    return {
      ok: true
      sgr: $"($prefix);($r);($g);($b)"
    }
  }

  # Indexed 256-color (ansi:0..255).
  let indexed = ($norm | parse --regex '^ansi:(?<n>\d+)$' | get -o 0)
  if $indexed != null {
    let n = (
      try {
        $indexed.n | into int
      } catch {
        -1
      }
    )
    if $n >= 0 and $n <= 255 {
      let prefix = if $channel == "bg" { "48;5" } else { "38;5" }
      return {
        ok: true
        sgr: $"($prefix);($n)"
      }
    }
    return {
      ok: false
      error: $"256-color index out of range 0..255: '($raw)'"
    }
  }

  {
    ok: false
    error: $"invalid color '($raw)'"
  }
}

def compile-slot [style: record]: nothing -> string {
  mut codes: list<string> = []
  for mod in $MODIFIER_CODES {
    if ($style | get -o $mod.name | default false) {
      $codes = ($codes | append $mod.code)
    }
  }
  if $style.fg != null {
    let fg_sgr = (parse-color $style.fg "fg").sgr
    if $fg_sgr != null {
      $codes = ($codes | append $fg_sgr)
    }
  }
  if $style.bg != null {
    let bg_sgr = (parse-color $style.bg "bg").sgr
    if $bg_sgr != null {
      $codes = ($codes | append $bg_sgr)
    }
  }

  if ($codes | is-empty) {
    ""
  } else {
    ansi --escape $"($codes | str join ';')m"
  }
}

def compile-palette [palette: record]: nothing -> record {
  mut compiled: record = {}
  for slot in $SLOTS {
    let style = ($EMPTY_STYLE | merge ($palette | get $slot))
    $compiled = ($compiled | insert $slot (compile-slot $style))
  }
  $compiled
}

def patch-slot [slot: string, base: record, patch: any]: nothing -> record {
  let kind = ($patch | describe)
  if $kind == "string" {
    let parsed = (parse-color $patch "fg")
    if not $parsed.ok {
      return {
        style: $base
        warning: $"theme override for '($slot)': ($parsed.error)"
      }
    }
    let next_fg = if $parsed.sgr == null { null } else { $patch }
    return {
      style: ($base | upsert fg $next_fg)
      warning: ""
    }
  }

  if not ($kind | str starts-with "record") {
    return {
      style: $base
      warning: $"theme override for '($slot)': expected color string or table, got ($kind)"
    }
  }

  if ($patch | is-empty) {
    return {
      style: $base
      warning: $"theme override for '($slot)': empty override table"
    }
  }

  mut next: record = $base
  for field in ($patch | transpose key value) {
    if $field.key in ["fg" "bg"] {
      let val_type = ($field.value | describe)
      if $val_type != "string" {
        return {
          style: $base
          warning: $"theme override for '($slot).($field.key)': expected string, got ($val_type)"
        }
      }
      let parsed = (parse-color $field.value $field.key)
      if not $parsed.ok {
        return {
          style: $base
          warning: $"theme override for '($slot).($field.key)': ($parsed.error)"
        }
      }
      let next_val = if $parsed.sgr == null { null } else { $field.value }
      $next = ($next | upsert $field.key $next_val)
    } else if $field.key in $MODIFIER_NAMES {
      let val_type = ($field.value | describe)
      if $val_type != "bool" {
        return {
          style: $base
          warning: $"theme override for '($slot).($field.key)': expected bool, got ($val_type)"
        }
      }
      $next = ($next | upsert $field.key $field.value)
    } else {
      return {
        style: $base
        warning: $"theme override for '($slot)': unknown field '($field.key)'"
      }
    }
  }

  {
    style: $next
    warning: ""
  }
}

# Return the compiled default ("ansi") theme record.
export def default-theme []: nothing -> record {
  compile-palette $PRESETS.ansi
}

# Resolve a normalized [theme] config and environment into compiled SGR prefixes and warnings.
export def resolve-theme [
  theme_cfg: record
  env_vars: record = {}
]: nothing -> record<theme: record, warnings: list<string>> {
  mut warnings: list<string> = []

  if $theme_cfg.invalid_section? != null {
    $warnings = (
      $warnings | append $"theme section must be a table, got ($theme_cfg.invalid_section)"
    )
  }

  let raw_preset = ($theme_cfg.preset? | default "ansi")
  let preset_name = if ($raw_preset | describe) == "string" and ($raw_preset in $PRESETS) {
    $raw_preset
  } else {
    let valid = ($PRESETS | columns | str join ", ")
    $warnings = ($warnings | append $"unknown theme preset '($raw_preset)' \(valid: ($valid)\)")
    "ansi"
  }

  let base_palette = ($PRESETS | get $preset_name)
  mut palette: record = {}
  for slot in $SLOTS {
    $palette = ($palette | insert $slot ($EMPTY_STYLE | merge ($base_palette | get $slot)))
  }

  let raw_overrides = ($theme_cfg.overrides? | default {})
  let overrides_kind = ($raw_overrides | describe)
  if not ($overrides_kind | str starts-with "record") {
    $warnings = ($warnings | append $"theme overrides must be a table, got ($overrides_kind)")
  } else {
    for entry in ($raw_overrides | transpose key value) {
      if $entry.key not-in $SLOTS {
        let valid = ($SLOTS | str join ", ")
        $warnings = ($warnings | append $"unknown theme slot '($entry.key)' \(valid: ($valid)\)")
      } else {
        let patched = (patch-slot $entry.key ($palette | get $entry.key) $entry.value)
        if ($patched.warning | is-not-empty) {
          $warnings = ($warnings | append $patched.warning)
        } else {
          $palette = ($palette | upsert $entry.key $patched.style)
        }
      }
    }
  }

  let no_color = ($env_vars.NO_COLOR? | default "" | into string | is-not-empty)
  let theme = if $no_color {
    $EMPTY_THEME
  } else {
    compile-palette $palette
  }

  {
    theme: $theme
    warnings: $warnings
  }
}
