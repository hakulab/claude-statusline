#!/usr/bin/env nu

# ==================================================================================================
# Context Window Segment Formatting Tests
# ==================================================================================================

use std/assert
use ../theme.nu [resolve-theme]
use ./context.nu [format-context]

def "test format-context handles empty and populated token usage with color thresholds" [] {
  let low = {
    context_window: {
      context_window_size: 200000
      current_usage: {
        input_tokens: 40000
      }
    }
  }
  let low_rendered = (format-context $low)
  assert equal ($low_rendered | ansi strip) "Ctx: 20% (40k/200k)"
  assert ($low_rendered | str contains (ansi green))

  let mid = {
    context_window: {
      context_window_size: 200000
      current_usage: {
        input_tokens: 40000
        cache_creation_input_tokens: 10000
        cache_read_input_tokens: 50000
      }
    }
  }
  let mid_rendered = (format-context $mid)
  assert equal ($mid_rendered | ansi strip) "Ctx: 50% (100k/200k)"
  assert ($mid_rendered | str contains (ansi yellow))

  let high = {
    context_window: {
      context_window_size: 200000
      current_usage: {
        input_tokens: 170000
      }
    }
  }
  let high_rendered = (format-context $high)
  assert equal ($high_rendered | ansi strip) "Ctx: 85% (170k/200k)"
  assert ($high_rendered | str contains (ansi red))

  assert equal (format-context {} | ansi strip) "Ctx: 0%"
}

def "test format-context applies custom and empty themes" [] {
  let mocha = (resolve-theme {preset: "catppuccin-mocha"}).theme
  let plain = (resolve-theme {} {NO_COLOR: "1"}).theme
  let high = {
    context_window: {
      context_window_size: 200000
      current_usage: {input_tokens: 170000}
    }
  }

  let styled = (format-context $high --theme $mocha)
  assert ($styled | str contains $mocha.muted)
  assert ($styled | str contains $mocha.error)
  assert equal (format-context $high --theme $plain) "Ctx: 85% (170k/200k)"
}
