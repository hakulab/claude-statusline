#!/usr/bin/env nu

# ==================================================================================================
# Segment Formatting Tests
# ==================================================================================================

use std/assert
use ./context.nu [format-context]
use ./cost.nu [format-block format-remaining format-today]
use ./git.nu [parse-branch work-counts]
use ./model.nu [model-name]

def "test parse-branch handles tracking, unborn, and detached headers" [] {
  assert equal (parse-branch "## main...origin/main [ahead 2, behind 1]") {
    branch: "main"
    ahead: 2
    behind: 1
  }
  assert equal (parse-branch "## No commits yet on feat/init") {
    branch: "feat/init"
    ahead: 0
    behind: 0
  }
  assert equal (parse-branch "## HEAD (no branch)") {
    branch: ""
    ahead: 0
    behind: 0
  }
}

def "test work-counts tallies staged, modified, and untracked entries" [] {
  let entries = [
    "M  src/main.nu"
    "A  src/new.nu"
    " M README.md"
    "?? scratch.txt"
    "?? notes.txt"
  ]
  assert equal (work-counts $entries) {
    staged: 2
    modified: 1
    untracked: 2
  }
}

def "test model-name maps aliases, 1M context, and effort level" [] {
  let models = {
    "claude-opus-4-6": "Opus 4.6"
  }
  let input = {
    model: {
      id: "claude-opus-4-6[1m]"
      display_name: "claude-opus-4-6[1m]"
    }
    context_window: {
      context_window_size: 1000000
    }
    effort: {
      level: "high"
    }
  }
  assert equal (model-name $input $models) "Opus 4.6 (1M) high"

  let fallback_input = {
    model: {
      id: "provider/custom-model"
      display_name: "provider/custom-model"
    }
  }
  assert equal (model-name $fallback_input $models) "custom-model"
}

def "test format-context handles empty and populated token usage" [] {
  assert equal (format-context {} | ansi strip) "Ctx: 0%"

  let input = {
    context_window: {
      context_window_size: 200000
      current_usage: {
        input_tokens: 40000
        cache_creation_input_tokens: 10000
        cache_read_input_tokens: 50000
      }
    }
  }
  assert equal (format-context $input | ansi strip) "Ctx: 50% (100k/200k)"
}

def "test format-remaining and format-block format active blocks" [] {
  assert equal (format-remaining 0) ""
  assert equal (format-remaining 45) "45m left"
  assert equal (format-remaining 125) "2h5m left"

  let block = {
    has_block: true
    block_cost: 4.5
    remaining_minutes: 125
    burn_rate: 1.75
  }
  assert equal (format-block $block | ansi strip) "Block: $4.50 (2h5m left, $1.75/h)"
  assert equal (format-block {has_block: false}) ""
}

def "test format-today renders combined and single-side values" [] {
  let local = {
    has_daily: true
    daily_cost: 40.75
  }
  let remote = {
    has_cost: true
    daily_cost: 198.11
  }
  assert equal (format-today $local [$remote] | ansi strip) "Today: $40.75 / $198.11"
  assert equal (format-today $local [] | ansi strip) "Today: $40.75"
  assert equal (format-today {} [$remote] | ansi strip) "Today: $198.11"
  assert equal (format-today {} [] | ansi strip) ""
}
