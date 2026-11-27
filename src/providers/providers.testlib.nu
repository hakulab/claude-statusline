# ==================================================================================================
# Shared Cost Provider Test Helpers
# ==================================================================================================

export def install-stub [src: path, dir: path, name: string]: nothing -> nothing {
  let target = ($dir | path join $name)
  let script = (open --raw $src | into string | str replace --regex '^#![^\r\n]*(\r?\n)?' "")
  $"#!($nu.current-exe) --no-config-file\n($script)" | save --force $target
  ^chmod +x $target
}

export def read-calls [log: path]: nothing -> list<record> {
  if ($log | path exists) {
    open $log | from json --objects
  } else {
    []
  }
}
