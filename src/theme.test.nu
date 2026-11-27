#!/usr/bin/env nu

# ==================================================================================================
# Theme Preset, Parsing, and Resolution Tests
# ==================================================================================================

use std/assert
use ./theme.nu [default-theme resolve-theme]

# --------------------------------------------------------------------------------------------------
# Built-in Presets
# --------------------------------------------------------------------------------------------------

def "test default-theme matches resolved ansi preset and Nushell ANSI codes" [] {
  let resolved = (
    resolve-theme {
      preset: "ansi"
      overrides: {}
    }
  )

  assert equal $resolved.warnings []
  assert equal (default-theme) $resolved.theme
  assert equal $resolved.theme {
    accent: (ansi blue_bold)
    info: (ansi cyan)
    success: (ansi green)
    warning: (ansi yellow)
    error: (ansi red)
    mode: (ansi magenta)
    muted: (ansi --escape "2m")
    separator: (ansi --escape "2m")
  }
}

def "test catppuccin presets compile expected truecolor SGR sequences" [] {
  let cases = [
    {
      preset: "catppuccin-mocha"
      expected: {
        accent: (ansi --escape "1;38;2;137;180;250m")
        info: (ansi --escape "38;2;148;226;213m")
        success: (ansi --escape "38;2;166;227;161m")
        warning: (ansi --escape "38;2;249;226;175m")
        error: (ansi --escape "38;2;243;139;168m")
        mode: (ansi --escape "38;2;203;166;247m")
        muted: (ansi --escape "38;2;166;173;200m")
        separator: (ansi --escape "38;2;88;91;112m")
      }
    }
    {
      preset: "catppuccin-latte"
      expected: {
        accent: (ansi --escape "1;38;2;30;102;245m")
        info: (ansi --escape "38;2;23;146;153m")
        success: (ansi --escape "38;2;64;160;43m")
        warning: (ansi --escape "38;2;223;142;29m")
        error: (ansi --escape "38;2;210;15;57m")
        mode: (ansi --escape "38;2;136;57;239m")
        muted: (ansi --escape "38;2;108;111;133m")
        separator: (ansi --escape "38;2;172;176;190m")
      }
    }
  ]

  for case in $cases {
    let resolved = (
      resolve-theme {
        preset: $case.preset
        overrides: {}
      }
    )

    assert equal $resolved.warnings [] $case.preset
    assert equal $resolved.theme $case.expected $case.preset
  }
}

# --------------------------------------------------------------------------------------------------
# Color Formats and Slot Overrides
# --------------------------------------------------------------------------------------------------

def "test color parsing handles hex, ANSI 16 aliases, 256-color, bg, and reset" [] {
  let cases = [
    {
      name: "hex with whitespace and uppercase"
      override: " #FE640B "
      expected: (ansi --escape "38;2;254;100;11m")
    }
    {
      name: "standard ANSI alias purple"
      override: "purple"
      expected: (ansi --escape "35m")
    }
    {
      name: "standard ANSI alias grey"
      override: "grey"
      expected: (ansi --escape "37m")
    }
    {
      name: "bright ANSI alias dark_gray"
      override: "dark_gray"
      expected: (ansi --escape "90m")
    }
    {
      name: "bright ANSI alias light_purple"
      override: "light_purple"
      expected: (ansi --escape "95m")
    }
    {
      name: "bright ANSI alias light_white"
      override: "light_white"
      expected: (ansi --escape "97m")
    }
    {
      name: "256-color min"
      override: "ansi:0"
      expected: (ansi --escape "38;5;0m")
    }
    {
      name: "256-color mid"
      override: "ANSI:174"
      expected: (ansi --escape "38;5;174m")
    }
    {
      name: "256-color max"
      override: "ansi:255"
      expected: (ansi --escape "38;5;255m")
    }
    {
      name: "reset clears foreground"
      override: "reset"
      expected: ""
    }
    {
      name: "default clears foreground"
      override: "default"
      expected: ""
    }
    {
      name: "bg ANSI bright and fg hex"
      override: {
        fg: "#1e66f5"
        bg: "bright_black"
      }
      expected: (ansi --escape "38;2;30;102;245;100m")
    }
    {
      name: "bg 256-color and hex"
      override: {
        fg: "reset"
        bg: "ansi:236"
      }
      expected: (ansi --escape "48;5;236m")
    }
    {
      name: "bg hex"
      override: {
        fg: "default"
        bg: "#1e1e2e"
      }
      expected: (ansi --escape "48;2;30;30;46m")
    }
  ]

  for case in $cases {
    let resolved = (
      resolve-theme {
        preset: "ansi"
        overrides: {info: $case.override}
      }
    )

    assert equal $resolved.warnings [] $case.name
    assert equal $resolved.theme.info $case.expected $case.name
  }
}

def "test slot overrides preserve inherited fields and compile modifiers in SGR order" [] {
  let cfg = {
    preset: "ansi"
    overrides: {
      accent: "#fe640b"
      muted: {
        fg: "#6c6f85"
        dim: false
      }
      separator: {
        dim: false
      }
      mode: {
        fg: "cyan"
        bg: "black"
        bold: true
        dim: true
        italic: true
        underlined: true
        reversed: true
      }
    }
  }

  let resolved = (resolve-theme $cfg)

  assert equal $resolved.warnings []
  assert equal $resolved.theme.accent (ansi --escape "1;38;2;254;100;11m")
  assert equal $resolved.theme.muted (ansi --escape "38;2;108;111;133m")
  assert equal $resolved.theme.separator ""
  assert equal $resolved.theme.mode (ansi --escape "1;2;3;4;7;36;40m")
}

# --------------------------------------------------------------------------------------------------
# Validation Warnings and Fallbacks
# --------------------------------------------------------------------------------------------------

def "test invalid theme config warns and falls back while keeping valid overrides" [] {
  let cases = [
    {
      name: "unknown preset"
      cfg: {
        preset: "unknown-theme"
        overrides: {info: "#179299"}
      }
      warning_match: "unknown theme preset 'unknown-theme'"
      slot: "info"
      expected: (ansi --escape "38;2;23;146;153m")
    }
    {
      name: "non-string preset"
      cfg: {
        preset: 42
        overrides: {}
      }
      warning_match: "unknown theme preset"
      slot: "accent"
      expected: (ansi blue_bold)
    }
    {
      name: "non-record overrides"
      cfg: {
        preset: "ansi"
        overrides: ["red"]
      }
      warning_match: "theme overrides must be a table"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "unknown slot"
      cfg: {
        preset: "ansi"
        overrides: {
          bogus: "red"
          info: "green"
        }
      }
      warning_match: "unknown theme slot 'bogus'"
      slot: "info"
      expected: (ansi green)
    }
    {
      name: "3-digit hex rejected"
      cfg: {
        preset: "ansi"
        overrides: {info: "#fff"}
      }
      warning_match: "invalid color '#fff'"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "256-color out of range"
      cfg: {
        preset: "ansi"
        overrides: {info: "ansi:256"}
      }
      warning_match: "256-color index out of range"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "256-color overflow"
      cfg: {
        preset: "ansi"
        overrides: {info: "ansi:999999999999999999999999"}
      }
      warning_match: "256-color index out of range"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "unknown color name"
      cfg: {
        preset: "ansi"
        overrides: {info: "chartreuse"}
      }
      warning_match: "invalid color 'chartreuse'"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "empty inline table"
      cfg: {
        preset: "ansi"
        overrides: {info: {}}
      }
      warning_match: "empty override table"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "unknown field in inline table"
      cfg: {
        preset: "ansi"
        overrides: {
          info: {
            fg: "red"
            underline: true
          }
        }
      }
      warning_match: "unknown field 'underline'"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "non-bool modifier"
      cfg: {
        preset: "ansi"
        overrides: {
          info: {bold: "yes"}
        }
      }
      warning_match: "expected bool"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "non-string fg"
      cfg: {
        preset: "ansi"
        overrides: {
          info: {fg: 123}
        }
      }
      warning_match: "expected string"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "non-string non-record override"
      cfg: {
        preset: "ansi"
        overrides: {info: 123}
      }
      warning_match: "expected color string or table"
      slot: "info"
      expected: (ansi cyan)
    }
    {
      name: "invalid theme section marker"
      cfg: {
        preset: "ansi"
        overrides: {}
        invalid_section: "string"
      }
      warning_match: "theme section must be a table"
      slot: "info"
      expected: (ansi cyan)
    }
  ]

  for case in $cases {
    let resolved = (resolve-theme $case.cfg)

    assert ($resolved.warnings | any {|w| $w | str contains $case.warning_match }) $case.name
    assert equal ($resolved.theme | get $case.slot) $case.expected $case.name
  }
}

# --------------------------------------------------------------------------------------------------
# NO_COLOR Handling
# --------------------------------------------------------------------------------------------------

def "test no-color disables all slots for any non-empty value and preserves warnings" [] {
  let empty_theme = {
    accent: ""
    info: ""
    success: ""
    warning: ""
    error: ""
    mode: ""
    muted: ""
    separator: ""
  }

  for val in ["1" "0" "true" "false"] {
    let resolved = (
      resolve-theme {
        preset: "catppuccin-mocha"
        overrides: {}
      } {NO_COLOR: $val}
    )

    assert equal $resolved.warnings [] $"NO_COLOR=($val)"
    assert equal $resolved.theme $empty_theme $"NO_COLOR=($val)"
  }

  let with_empty = (
    resolve-theme {
      preset: "ansi"
      overrides: {}
    } {NO_COLOR: ""}
  )
  assert equal $with_empty.theme (default-theme)

  let with_warning = (
    resolve-theme {
      preset: "bogus"
      overrides: {}
    } {NO_COLOR: "1"}
  )
  assert equal $with_warning.theme $empty_theme
  assert ($with_warning.warnings | any {|w| $w | str contains "unknown theme preset" })
}
