# ==================================================================================================
# Local ccusage Cost Provider
# ==================================================================================================

use ./common.nu [parse-json-record]

export const CCUSAGE_SPEC = {
  cache_name: "statusline-usage.json"
  lock_name: "statusline-usage.lock"
  refresh: "ccusage"
  fields: [
    "date"
    "has_block"
    "has_daily"
    "block_cost"
    "remaining_minutes"
    "burn_rate"
    "daily_cost"
  ]
}

export const DAILY_SPEC = {
  cache_name: "statusline-daily.json"
  lock_name: "statusline-daily.lock"
  refresh: "ccusage-daily"
  fields: [
    "date"
    "has_daily"
    "daily_cost"
  ]
}

export def ccusage-json [args: list<string>]: nothing -> record {
  let result = (
    ^ccusage claude ...$args
      --json
      --offline
    | complete
  )
  if $result.exit_code != 0 {
    error make {msg: $"ccusage ($args | str join ' ') exited ($result.exit_code)"}
  }
  parse-json-record $result.stdout $"ccusage ($args | str join ' ')"
}

export def current-ccusage [--with-blocks]: nothing -> record {
  let today = (date now | format date "%Y%m%d")
  let block_fields = if $with_blocks {
    let blocks = (ccusage-json [blocks --active])
    let active = (
      $blocks.blocks?
      | default []
      | where ($it.isActive? | default false)
      | get -o 0
    )
    {
      has_block: ($active != null)
      block_cost: ($active.costUSD? | default 0 | into float)
      remaining_minutes: ($active.projection?.remainingMinutes? | default 0 | math floor)
      burn_rate: ($active.burnRate?.costPerHour? | default 0 | into float)
    }
  } else {
    {}
  }
  let daily = (ccusage-json [
    daily
      --since $today
      --until $today
  ])
  let daily_cost = $daily.totals?.totalCost?

  (
    {
      date: $today
      has_daily: ($daily_cost != null)
      daily_cost: ($daily_cost | default 0 | into float)
    }
    | merge $block_fields
  )
}
