# ==================================================================================================
# Shared Cost Provider Helpers
# ==================================================================================================

export def non-empty-file [file: string]: nothing -> bool {
  if ($file | is-empty) or not ($file | path exists) {
    return false
  }
  try {
    let text = (open --raw $file | into string)
    $text | str trim | is-not-empty
  } catch {
    false
  }
}

export def parse-json-record [text: string, label: string]: nothing -> record {
  let parsed = (
    try {
      $text | from json
    } catch {
      error make {msg: $"($label) returned invalid JSON"}
    }
  )
  if not ($parsed | describe | str starts-with "record") {
    error make {msg: $"($label) returned invalid JSON"}
  }
  $parsed
}

export def parse-finite-float [value: any, error_msg: string]: nothing -> float {
  let kind = ($value | describe)
  if $kind not-in ["int" "float" "string"] {
    error make {msg: $error_msg}
  }
  let candidate = if $kind == "string" { $value | str trim } else { $value }
  let num = (
    try {
      $candidate | into float
    } catch {
      error make {msg: $error_msg}
    }
  )
  if ($num != $num) or (($num | into string) in ["inf" "-inf"]) {
    error make {msg: $error_msg}
  }
  $num
}

export def extract-cost [parsed: any, path: list<string>, label: string]: nothing -> float {
  if ($path | is-empty) {
    error make {msg: $"($label) extract path must not be empty"}
  }
  let value = (
    $path
    | reduce --fold $parsed {|segment, current|
      if $current == null {
        null
      } else if ($current | describe | str starts-with "record") {
        $current | get -o $segment
      } else {
        null
      }
    }
  )
  if $value == null {
    error make {msg: $"($label) response missing ($path | str join '.')"}
  }
  parse-finite-float $value $"($label) ($path | str join '.') is not numeric"
}

export def source-cache-spec [source_id: string]: nothing -> record {
  let safe_id = ($source_id | str replace --all --regex '[^A-Za-z0-9._-]' "_")
  {
    cache_name: $"statusline-source-($safe_id).json"
    lock_name: $"statusline-source-($safe_id).lock"
    refresh: $"source:($source_id)"
    fields: [
      "date"
      "has_cost"
      "daily_cost"
    ]
  }
}
