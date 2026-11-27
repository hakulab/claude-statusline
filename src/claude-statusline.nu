#!/usr/bin/env nu

# ==================================================================================================
# Claude Code Status Line
# ==================================================================================================
# Renders configurable rows of segments (default: dir + git on row 1; model, context, block, today,
# and time on row 2) with lazy execution and stale-while-revalidate cost caching.
# ==================================================================================================

use ./cache.nu [read-cached write-cache]
use ./config.nu [active-cost-sources load-config row-separator should-show-block]
use ./format.nu [dim]
use ./providers/ccusage.nu [CCUSAGE_SPEC DAILY_SPEC current-ccusage]
use ./providers/command.nu [fetch-command]
use ./providers/common.nu [source-cache-spec]
use ./providers/http.nu [auth-ready fetch-http]
use ./segments/basic.nu [format-dir format-mode format-time input-cwd]
use ./segments/context.nu [format-context]
use ./segments/cost.nu [format-block format-session format-today]
use ./segments/git.nu [format-git-info]
use ./segments/model.nu [format-model]

const SCRIPT_PATH = path self

def default-cache-dir []: nothing -> path {
  let home = ($env.HOME? | default --empty $nu.home-dir)
  let cache_home = ($env.XDG_CACHE_HOME? | default --empty ($home | path join ".cache"))
  $cache_home | path join "claude-statusline"
}

def read-input []: nothing -> record {
  # `open /dev/stdin` re-opens fd 0 by path, which fails with ENXIO when the caller passes a
  # socket, as Claude Code's spawn does.
  let raw = (^cat | str trim)
  if ($raw | is-empty) {
    return {}
  }
  let parsed = (try { $raw | from json } catch { {} })
  if ($parsed | describe | str starts-with "record") {
    $parsed
  } else {
    {}
  }
}

def refresh-source [source_id: string, cache_dir: path, config: record]: nothing -> nothing {
  let entry = ($config.cost_sources | where id == $source_id | get -o 0)
  if $entry == null {
    error make {msg: $"unknown cost source: ($source_id)"}
  }
  let spec = (source-cache-spec $entry.id)
  let source_cfg = $entry.source
  let kind = ($source_cfg.type? | default "")
  let data = match $kind {
    "http" => { fetch-http $source_cfg $config.defaults.timeout $env $"cost source ($entry.id)" }
    "command" => { fetch-command $source_cfg $config.defaults.timeout $"cost source ($entry.id)" }
    _ => { error make {msg: $"unsupported cost source type for ($entry.id): ($kind)"} }
  }
  write-cache ($cache_dir | path join $spec.cache_name) $data
}

def refresh-target [target: string, cache_dir: path, config: record]: nothing -> nothing {
  if ($target | str starts-with "source:") {
    let source_id = ($target | str substring 7..)
    refresh-source $source_id $cache_dir $config
    return
  }

  match $target {
    "ccusage" => {
      write-cache ($cache_dir | path join $CCUSAGE_SPEC.cache_name) (current-ccusage --with-blocks)
    }
    "ccusage-daily" => {
      write-cache ($cache_dir | path join $DAILY_SPEC.cache_name) (current-ccusage)
    }
    _ => {
      error make {msg: $"unknown refresh target: ($target)"}
    }
  }
}

def source-ready [entry: record, env_vars: record]: nothing -> bool {
  let source_cfg = $entry.source
  match ($source_cfg.type? | default "") {
    "http" => {
      ($source_cfg.url? | default "" | is-not-empty) and (
        auth-ready ($source_cfg.auth? | default {}) $env_vars
      )
    }
    "command" => { $source_cfg.argv? | default [] | is-not-empty }
    _ => false
  }
}

def join-row [parts: list<string>, separator: string]: nothing -> string {
  let non_empty = ($parts | compact --empty)
  if ($non_empty | is-empty) {
    return ""
  }
  let sep = if ($separator | str trim | is-empty) {
    $separator
  } else {
    dim $separator
  }
  $non_empty | str join $sep
}

def render-segment [
  name: string
  input: record
  config: record
  git_info: string
  local_usage: record
  remote_usages: list<record>
  show_block: bool
]: nothing -> string {
  match $name {
    "dir" => { format-dir $input }
    "git" => $git_info
    "model" => { format-model $input $config.models }
    "context" => { format-context $input }
    "session" => { format-session $input }
    "mode" => { format-mode $input }
    "block" => { if $show_block { format-block $local_usage } else { "" } }
    "today" => { format-today $local_usage $remote_usages }
    "time" => { format-time }
    _ => ""
  }
}

# Render a configurable Claude Code status line from JSON on stdin.
def main [
  --config: string = "" # Path to TOML or JSON configuration file
  --cache-dir: string = "" # Cache directory (default: $XDG_CACHE_HOME/claude-statusline)
  --refresh: string = "" # Refresh target to write and exit: ccusage, ccusage-daily, or source:<id>
  --sync-refresh # Wait for cache refreshes to complete before exiting
] {
  let effective_cache_dir = if ($cache_dir | is-not-empty) {
    $cache_dir
  } else {
    default-cache-dir
  }
  let config_data = (load-config $config)
  if ($refresh | is-not-empty) {
    refresh-target $refresh $effective_cache_dir $config_data
    return
  }

  let input = (read-input)
  let active_segments = ($config_data.layout.rows | flatten | uniq)
  let needs_git = ("git" in $active_segments)
  let needs_block = ("block" in $active_segments)
  let needs_today = ("today" in $active_segments)
  let needs_cost = ($needs_block or $needs_today)

  let cwd = (input-cwd $input)
  let git_info = if $needs_git { format-git-info $cwd } else { "" }

  let matched = if $needs_cost { active-cost-sources $config_data $env } else { [] }
  let show_block = ($needs_block and (should-show-block $matched))

  let local_usage = if $config_data.local.provider == "ccusage" and ($show_block or $needs_today) {
    let spec = if $show_block { $CCUSAGE_SPEC } else { $DAILY_SPEC }
    (
      read-cached
        $effective_cache_dir
        $spec
        $SCRIPT_PATH
        $config
        $config_data.defaults.cache_ttl
        $config_data.defaults.max_stale
        --sync-refresh=$sync_refresh
    )
  } else {
    {}
  }

  let remote_usages = if $needs_today {
    $matched
    | where {|entry| source-ready $entry $env }
    | each {|entry|
      let spec = (source-cache-spec $entry.id)
      (
        read-cached
          $effective_cache_dir
          $spec
          $SCRIPT_PATH
          $config
          $entry.behavior.cache_ttl
          $entry.behavior.max_stale
          --sync-refresh=$sync_refresh
      )
    }
  } else {
    []
  }

  let rows = (
    $config_data.layout.rows
    | enumerate
    | each {|row|
      let parts = (
        $row.item
        | each {|segment|
          (
            render-segment
              $segment
              $input
              $config_data
              $git_info
              $local_usage
              $remote_usages
              $show_block
          )
        }
      )
      join-row $parts (row-separator $config_data.layout $row.index)
    }
    | compact --empty
  )

  print --no-newline ($rows | str join "\n")
}
