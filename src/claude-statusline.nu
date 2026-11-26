#!/usr/bin/env nu

# ==================================================================================================
# Claude Code Status Line
# ==================================================================================================
# Row 1: <directory> <git>
# Row 2: Model | Ctx: X% (XXk/1000k) | [Block: ...] | [Today: $local / $remote] | HH:MM
# ==================================================================================================

use ./cache.nu [read-cached write-cache]
use ./config.nu [active-cost-sources load-config should-show-block]
use ./format.nu [dim paint]
use ./providers/ccusage.nu [CCUSAGE_SPEC DAILY_SPEC current-ccusage]
use ./providers/command.nu [fetch-command]
use ./providers/common.nu [source-cache-spec]
use ./providers/http.nu [auth-ready fetch-http]
use ./segments/context.nu [format-context]
use ./segments/cost.nu [format-block format-today]
use ./segments/git.nu [format-git-info]
use ./segments/model.nu [model-name]

const SCRIPT_PATH = path self
const DEFAULT_CACHE_DIR = $nu.cache-dir | path join "claude-statusline"

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

# Render a two-row Claude Code status line from JSON on stdin.
def main [
  --config: string = "" # Path to TOML or JSON configuration file
  --cache-dir: path = $DEFAULT_CACHE_DIR # Shared cache directory for concurrent status lines
  --refresh: string = "" # Refresh target to write and exit: ccusage, ccusage-daily, or source:<id>
  --sync-refresh # Wait for cache refreshes to complete before exiting
] {
  let config_data = (load-config $config)
  if ($refresh | is-not-empty) {
    refresh-target $refresh $cache_dir $config_data
    return
  }

  # `open /dev/stdin` re-opens fd 0 by path, which fails with ENXIO when the caller passes a
  # socket, as Claude Code's spawn does.
  let input = (^cat | from json)
  let cwd = $input.workspace.current_dir
  let home = ($env.HOME? | default $nu.home-dir)

  let dir_name = if $cwd == $home {
    "~"
  } else {
    $cwd | path basename
  }
  let row1 = $"(paint $dir_name "blue_bold")(format-git-info $cwd)"

  let model = (model-name $input $config_data.models)
  let ctx = (format-context $input)
  let matched = (active-cost-sources $config_data $env)
  let show_block = (should-show-block $config_data $matched)

  let local_usage = if $config_data.local.provider == "ccusage" {
    let spec = if $show_block { $CCUSAGE_SPEC } else { $DAILY_SPEC }
    (
      read-cached
        $cache_dir
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

  let remote_usages = (
    $matched
    | where {|entry| source-ready $entry $env }
    | each {|entry|
      let spec = (source-cache-spec $entry.id)
      (
        read-cached
          $cache_dir
          $spec
          $SCRIPT_PATH
          $config
          $entry.behavior.cache_ttl
          $entry.behavior.max_stale
          --sync-refresh=$sync_refresh
      )
    }
  )

  let row2 = (
    [
      (if ($model | is-not-empty) { paint $model "cyan" })
      $ctx
      (if $show_block { format-block $local_usage })
      (format-today $local_usage $remote_usages)
      (dim (date now | format date "%H:%M"))
    ]
    | compact --empty
    | str join $" (dim "|") "
  )

  print --no-newline $"($row1)\n($row2)"
}
