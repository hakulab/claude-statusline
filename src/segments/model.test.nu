#!/usr/bin/env nu

# ==================================================================================================
# Model Segment Formatting Tests
# ==================================================================================================

use std/assert
use ../theme.nu [resolve-theme]
use ./model.nu [format-model model-name]

def "test model-name maps aliases, 1M context, effort, and fallbacks" [] {
  let models = {
    "claude-opus-5-5": "Opus 5.5"
    "claude-sonnet-5-5": "Sonnet 5.5"
  }
  let aliased = {
    model: {
      id: "claude-opus-5-5[1m]"
      display_name: "claude-opus-5-5[1m]"
    }
    context_window: {
      context_window_size: 1000000
    }
    effort: {
      level: "high"
    }
  }
  assert equal (model-name $aliased $models) "Opus 5.5 (1M) high"
  assert equal (format-model $aliased $models | ansi strip) "Opus 5.5 (1M) high"

  let display_fallback = {
    model: {
      id: "claude-haiku-5-5"
      display_name: "Haiku 5.5 (1M context)"
    }
  }
  assert equal (model-name $display_fallback $models) "Haiku 5.5 (1M)"

  let id_fallback = {
    model: {
      id: "provider/custom-model"
      display_name: "provider/custom-model"
    }
  }
  assert equal (model-name $id_fallback $models) "custom-model"
  assert equal (format-model {} $models) ""

  let latte = (resolve-theme {preset: "catppuccin-latte"}).theme
  let plain = (resolve-theme {} {NO_COLOR: "1"}).theme
  assert (format-model $id_fallback $models --theme $latte | str contains $latte.info)
  assert equal (format-model $id_fallback $models --theme $plain) "custom-model"
}
