#!/usr/bin/env nu

# ==================================================================================================
# Segment Formatting Tests
# ==================================================================================================

use std/assert
use ./basic.nu [format-dir format-mode format-time]
use ./context.nu [format-context]
use ./cost.nu [format-block format-remaining format-session format-today]
use ./git.nu [format-git-info parse-branch work-counts]
use ./model.nu [format-model model-name]

# --------------------------------------------------------------------------------------------------
# Directory Segment
# --------------------------------------------------------------------------------------------------

def "test format-dir renders basename, home tilde, root, cwd fallback, and omits empty cwd" [] {
  assert equal (format-dir {workspace: {current_dir: "/tmp/my-project"}} "/home/user" | ansi strip) (
    "my-project"
  )
  assert equal (format-dir {workspace: {current_dir: "/home/user"}} "/home/user" | ansi strip) "~"
  assert equal (format-dir {workspace: {current_dir: "/"}} "/home/user" | ansi strip) "/"
  assert equal (format-dir {cwd: "/tmp/fallback"} "/home/user" | ansi strip) "fallback"
  assert equal (format-dir {} "/home/user") ""
}

# --------------------------------------------------------------------------------------------------
# Git Segment
# --------------------------------------------------------------------------------------------------

def "test parse-branch handles tracking, unborn, detached, and invalid headers" [] {
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
  assert equal (parse-branch "") {
    branch: ""
    ahead: 0
    behind: 0
  }
}

def "test work-counts tallies staged, modified, and untracked entries" [] {
  let entries = [
    "M  src/main.nu"
    "A  src/new.nu"
    "D  src/deleted.nu"
    "R  src/old.nu -> src/renamed.nu"
    "C  src/copy.nu"
    "MM src/both.nu"
    "AM src/added-then-edited.nu"
    " M README.md"
    " D removed-worktree.txt"
    " T symlink.txt"
    "?? scratch.txt"
    "?? notes.txt"
    "!! ignored.log"
  ]
  assert equal (work-counts $entries) {
    staged: 7
    modified: 5
    untracked: 2
  }
}

def "test format-git-info renders clean repo, dirty marks, and omits non-git dirs" [] {
  let non_git = (mktemp --directory)
  assert equal (format-git-info $non_git) ""
  assert equal (format-git-info "") ""

  let repo = (mktemp --directory)
  ^git -C $repo init --initial-branch=main | complete | ignore
  ^git -C $repo config user.name "Test" | complete | ignore
  ^git -C $repo config user.email "test@example.com" | complete | ignore
  "hello\n" | save ($repo | path join "tracked.txt")
  ^git -C $repo add tracked.txt | complete | ignore
  ^git -C $repo commit -m "init" | complete | ignore

  let clean = (format-git-info $repo)
  assert equal ($clean | ansi strip) "main"
  assert not ($clean | str contains (ansi yellow))

  "changed\n" | save --force ($repo | path join "tracked.txt")
  "staged\n" | save ($repo | path join "staged.txt")
  ^git -C $repo add staged.txt | complete | ignore
  "new\n" | save ($repo | path join "untracked.txt")

  assert equal (format-git-info $repo | ansi strip) "main +1 !1 ?1"
}

# --------------------------------------------------------------------------------------------------
# Mode Segment
# --------------------------------------------------------------------------------------------------

def "test format-mode renders vim mode and omits missing or blank values" [] {
  assert equal (format-mode {vim: {mode: "NORMAL"}} | ansi strip) "NORMAL"
  assert equal (format-mode {vim: {mode: " INSERT "}} | ansi strip) "INSERT"
  assert equal (format-mode {vim: {mode: "   "}}) ""
  assert equal (format-mode {}) ""
}

# --------------------------------------------------------------------------------------------------
# Model Segment
# --------------------------------------------------------------------------------------------------

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
}

# --------------------------------------------------------------------------------------------------
# Context Segment
# --------------------------------------------------------------------------------------------------

def "test format-context handles empty and populated token usage with color thresholds" [] {
  assert equal (format-context {} | ansi strip) "Ctx: 0%"

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
}

# --------------------------------------------------------------------------------------------------
# Session, Block, and Today Segments
# --------------------------------------------------------------------------------------------------

def "test format-session formats cost, zero, and omits missing or invalid values" [] {
  assert equal (format-session {cost: {total_cost_usd: 1.234}} | ansi strip) "Sess: $1.23"
  assert equal (format-session {cost: {total_cost_usd: 0}} | ansi strip) "Sess: $0.00"
  assert equal (format-session {}) ""
  assert equal (format-session {cost: {total_cost_usd: "bad"}}) ""
}

def "test format-remaining and format-block format active and inactive blocks" [] {
  assert equal (format-remaining 0) ""
  assert equal (format-remaining 45) "45m left"
  assert equal (format-remaining 125) "2h5m left"

  let full_block = {
    has_block: true
    block_cost: 4.5
    remaining_minutes: 125
    burn_rate: 1.75
  }
  assert equal (format-block $full_block | ansi strip) "Block: $4.50 (2h5m left, $1.75/h)"

  let bare_block = {
    has_block: true
    block_cost: 2.0
    remaining_minutes: 0
    burn_rate: 0.0
  }
  assert equal (format-block $bare_block | ansi strip) "Block: $2.00"
  assert equal (format-block {has_block: false}) ""
}

def "test format-today renders combined, single-side, and empty values" [] {
  let local = {
    has_daily: true
    daily_cost: 40.75
  }
  let remote_a = {
    has_cost: true
    daily_cost: 198.11
  }
  let remote_b = {
    has_cost: true
    daily_cost: 12.5
  }
  assert equal (format-today $local [$remote_a] | ansi strip) "Today: $40.75 / $198.11"
  assert equal (format-today $local [$remote_a $remote_b] | ansi strip) (
    "Today: $40.75 / $198.11 / $12.50"
  )
  assert equal (format-today $local [] | ansi strip) "Today: $40.75"
  assert equal (format-today {} [$remote_a] | ansi strip) "Today: $198.11"
  assert equal (format-today {} [] | ansi strip) ""
}

# --------------------------------------------------------------------------------------------------
# Time Segment
# --------------------------------------------------------------------------------------------------

def "test format-time formats HH:MM" [] {
  let dt = ("2026-11-26T14:35:00Z" | into datetime)
  assert equal (format-time $dt | ansi strip) "14:35"
}
