# ==================================================================================================
# Shared Stale-While-Revalidate Cache
# ==================================================================================================

def modified-time [path: path]: nothing -> datetime {
  let expanded = ($path | path expand)
  ls ($expanded | path dirname) | where name == $expanded | get 0.modified
}

export def cache-valid [cached: any, fields: list<string>]: nothing -> bool {
  (
    ($cached | describe | str starts-with "record")
    and ($fields | all {|field| $field in $cached })
    and ($cached.date == (date now | format date "%Y%m%d"))
  )
}

export def read-cache [cache: path, fields: list<string>, max_age: duration]: nothing -> record {
  let cached = (try {
    if not ($cache | path exists) {
      null
    } else if ((date now) - (modified-time $cache)) >= $max_age {
      null
    } else {
      open $cache
    }
  } catch {
    null
  })
  if $cached != null and (cache-valid $cached $fields) {
    $cached
  } else {
    {}
  }
}

def temp-cache-path [cache: path]: nothing -> path {
  $"($cache).($nu.pid).tmp"
}

export def write-cache [cache: path, data: record]: nothing -> nothing {
  let tmp = (temp-cache-path $cache)
  try {
    $data
    | to json
    | save --force --raw $tmp
  } catch {
    ^rm -f $tmp | complete | ignore
    error make {msg: "failed to write usage cache"}
  }

  let moved = (^mv --force $tmp $cache | complete)
  if $moved.exit_code != 0 {
    ^rm -f $tmp | complete | ignore
    error make {msg: "failed to publish usage cache"}
  }
}

# Contenders must lock the same inode, so lock files stay allocated and are never deleted.
export def spawn-refresh [
  lock: path
  script_path: path
  config_path: string
  cache_dir: path
  target: string
  --sync-refresh
]: nothing -> nothing {
  let config_args = if ($config_path | is-not-empty) {
    ["--config" $config_path]
  } else {
    []
  }
  let args = [
    ...$config_args
    "--cache-dir" $cache_dir
    "--refresh" $target
  ]
  if $sync_refresh {
    (
      ^flock --nonblock $lock $nu.current-exe --no-config-file $script_path ...$args
      | complete
      | ignore
    )
  } else {
    # Detach stdio to /dev/null so the caller's stdout pipe reaches EOF without waiting.
    (
      ^bash -c '"$@" </dev/null >/dev/null 2>&1 &' _
        flock --nonblock $lock $nu.current-exe --no-config-file $script_path ...$args
      | complete
      | ignore
    )
  }
}

export def read-cached [
  cache_dir: path
  spec: record<cache_name: string, lock_name: string, refresh: string, fields: list<string>>
  script_path: path
  config_path: string
  ttl: duration
  max_stale: duration
  --sync-refresh
]: nothing -> record {
  let cache = ($cache_dir | path join $spec.cache_name)
  let fresh = (read-cache $cache $spec.fields $ttl)
  if ($fresh | is-not-empty) {
    return $fresh
  }

  let stale = (read-cache $cache $spec.fields $max_stale)
  ^mkdir -p $cache_dir | complete | ignore
  let lock = ($cache_dir | path join $spec.lock_name)
  (
    spawn-refresh $lock $script_path $config_path $cache_dir $spec.refresh
      --sync-refresh=$sync_refresh
  )
  $stale
}
