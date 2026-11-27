# ==================================================================================================
# Basic Segments (Directory, Mode, Time)
# ==================================================================================================

use ../format.nu [paint]
use ../theme.nu [default-theme]

export def input-cwd [input: record]: nothing -> string {
  $input.workspace?.current_dir?
  | default --empty ($input.cwd? | default "")
}

export def format-dir [input: record, home: string = "", --theme: record]: nothing -> string {
  let cwd = (input-cwd $input)
  if ($cwd | is-empty) {
    return ""
  }
  let t = ($theme | default (default-theme))
  let effective_home = if ($home | is-not-empty) {
    $home
  } else {
    $env.HOME? | default --empty $nu.home-dir
  }
  let label = if $cwd == $effective_home {
    "~"
  } else {
    $cwd | path basename | default --empty "/"
  }
  paint $label $t.accent
}

export def format-mode [input: record, --theme: record]: nothing -> string {
  let mode = ($input.vim?.mode? | default "" | into string | str trim)
  if ($mode | is-empty) {
    ""
  } else {
    let t = ($theme | default (default-theme))
    paint $mode $t.mode
  }
}

export def format-time [now?: datetime, --theme: record]: nothing -> string {
  let t = ($theme | default (default-theme))
  let timestamp = ($now | default (date now))
  paint ($timestamp | format date "%H:%M") $t.muted
}
