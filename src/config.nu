# ==================================================================================================
# Configuration Loader and Source Matcher
# ==================================================================================================

use ./time.nu [parse-duration]

const DEFAULT_CACHE_TTL = 60sec
const DEFAULT_MAX_STALE = 15min
const DEFAULT_TIMEOUT = 5sec

const DEFAULT_ROWS = [
  ["dir" "git"]
  ["model" "context" "block" "today" "time"]
]

const DEFAULT_ROW0_SEPARATOR = " "
const DEFAULT_SEPARATOR = " | "

const DEFAULT_THEME = {
  preset: "catppuccin-mocha"
  overrides: {}
}

const OFFICIAL_ANTHROPIC_BASE_URL = "https://api.anthropic.com"

const NON_SUBSCRIPTION_ENV_KEYS = [
  "ANTHROPIC_API_KEY"
  "ANTHROPIC_AUTH_TOKEN"
]

const CLOUD_PROVIDER_ENV_KEYS = [
  "CLAUDE_CODE_USE_BEDROCK"
  "CLAUDE_CODE_USE_VERTEX"
  "CLAUDE_CODE_USE_FOUNDRY"
]

const TRUTHY_ENV_VALUES = [
  "1"
  "true"
  "yes"
  "on"
]

# --------------------------------------------------------------------------------------------------
# Defaults and Config Loading
# --------------------------------------------------------------------------------------------------

export def default-config-path []: nothing -> path {
  let home = ($env.HOME? | default --empty $nu.home-dir)
  let config_home = ($env.XDG_CONFIG_HOME? | default --empty ($home | path join ".config"))
  $config_home | path join "claude-statusline/config.toml"
}

export def default-config []: nothing -> record {
  {
    defaults: {
      cache_ttl: $DEFAULT_CACHE_TTL
      max_stale: $DEFAULT_MAX_STALE
      timeout: $DEFAULT_TIMEOUT
    }
    layout: {
      rows: $DEFAULT_ROWS
      separator: $DEFAULT_SEPARATOR
      separators: []
    }
    theme: $DEFAULT_THEME
    local: {
      provider: "ccusage"
    }
    models: {}
    cost_sources: []
  }
}

def normalize-defaults [raw: record]: nothing -> record {
  {
    cache_ttl: (parse-duration ($raw.cache_ttl?) $DEFAULT_CACHE_TTL)
    max_stale: (parse-duration ($raw.max_stale?) $DEFAULT_MAX_STALE)
    timeout: (parse-duration ($raw.timeout?) $DEFAULT_TIMEOUT)
  }
}

def normalize-layout [raw: record]: nothing -> record {
  {
    rows: ($raw.rows? | default $DEFAULT_ROWS)
    separator: ($raw.separator? | default $DEFAULT_SEPARATOR)
    separators: ($raw.separators? | default [])
  }
}

def normalize-theme [raw: any]: nothing -> record {
  if $raw == null {
    return $DEFAULT_THEME
  }
  if not ($raw | describe | str starts-with "record") {
    return {
      preset: $DEFAULT_THEME.preset
      overrides: {}
      invalid_section: ($raw | describe)
    }
  }
  (
    $raw
    | upsert preset ($raw.preset? | default $DEFAULT_THEME.preset)
    | upsert overrides ($raw.overrides? | default {})
  )
}

def normalize-local [raw: record]: nothing -> record {
  {
    provider: ($raw.provider? | default "ccusage")
  }
}

def normalize-cost-source [raw: record]: nothing -> record {
  {
    id: ($raw.id? | default "")
    match: ($raw.match? | default {})
    source: ($raw.source? | default {})
  }
}

export def load-config [config_path: string = ""]: nothing -> record {
  let explicit = ($config_path | is-not-empty)
  let target = if $explicit {
    $config_path
  } else {
    default-config-path
  }

  if not ($target | path exists) {
    if $explicit {
      error make {msg: $"config file not found: ($target)"}
    }
    return (default-config)
  }

  let raw = (open $target)
  if not ($raw | describe | str starts-with "record") {
    error make {msg: $"config file must contain a table or record: ($target)"}
  }

  let sources = (
    $raw.cost_sources?
    | default []
    | each {|entry| normalize-cost-source $entry }
  )

  {
    defaults: (normalize-defaults ($raw.defaults? | default {}))
    layout: (normalize-layout ($raw.layout? | default {}))
    theme: (normalize-theme ($raw.theme?))
    local: (normalize-local ($raw.local? | default {}))
    models: ($raw.models? | default {})
    cost_sources: $sources
  }
}

# --------------------------------------------------------------------------------------------------
# Block Visibility and Cost Source Matching
# --------------------------------------------------------------------------------------------------

def env-string [env_vars: record, key: string]: nothing -> string {
  $env_vars | get -o $key | default "" | into string | str trim
}

def env-truthy [env_vars: record, key: string]: nothing -> bool {
  (env-string $env_vars $key | str lowercase) in $TRUTHY_ENV_VALUES
}

def has-custom-base-url [env_vars: record]: nothing -> bool {
  let raw = (env-string $env_vars "ANTHROPIC_BASE_URL")
  if ($raw | is-empty) {
    return false
  }
  ($raw | str trim --right --char "/" | str lowercase) != $OFFICIAL_ANTHROPIC_BASE_URL
}

export def should-show-block [env_vars: record]: nothing -> bool {
  let has_api_auth = (
    $NON_SUBSCRIPTION_ENV_KEYS | any {|key| env-string $env_vars $key | is-not-empty }
  )
  let has_cloud_provider = (
    $CLOUD_PROVIDER_ENV_KEYS | any {|key| env-truthy $env_vars $key }
  )
  not ($has_api_auth or $has_cloud_provider or (has-custom-base-url $env_vars))
}

# For HTTP(S) prefixes, require an exact match or a `/` boundary so `https://api.example.com`
# does not match `https://api.example.com.evil.test`.
def prefix-matches [value: string, prefix: string]: nothing -> bool {
  if ($value | is-empty) or ($prefix | is-empty) {
    return false
  }
  if ($prefix | str starts-with "http://") or ($prefix | str starts-with "https://") {
    let norm_val = ($value | str trim --right --char "/")
    let norm_prefix = ($prefix | str trim --right --char "/")
    $norm_val == $norm_prefix or ($norm_val | str starts-with $"($norm_prefix)/")
  } else {
    $value | str starts-with $prefix
  }
}

export def source-matches [entry: record, env_vars: record]: nothing -> bool {
  let matcher = ($entry.match? | default {})
  let prefixes = ($matcher.env_prefix? | default {})
  let required = ($matcher.env_exists? | default [])

  let prefix_ok = (
    $prefixes
    | transpose key prefix
    | all {|rule|
      let val = ($env_vars | get -o $rule.key | default "" | into string)
      prefix-matches $val ($rule.prefix | into string)
    }
  )
  let exists_ok = (
    $required
    | all {|key| env-string $env_vars $key | is-not-empty }
  )

  $prefix_ok and $exists_ok
}

export def active-cost-sources [config: record, env_vars: record]: nothing -> list<record> {
  $config.cost_sources
  | where {|entry| ($entry.id | is-not-empty) and (source-matches $entry $env_vars) }
}

# --------------------------------------------------------------------------------------------------
# Layout Separators
# --------------------------------------------------------------------------------------------------

export def row-separator [layout: record, index: int]: nothing -> string {
  let override = ($layout.separators | get -o $index)
  if $override != null {
    $override
  } else if $index == 0 {
    $DEFAULT_ROW0_SEPARATOR
  } else {
    $layout.separator
  }
}
