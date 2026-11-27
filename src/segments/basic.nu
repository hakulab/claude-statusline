# ==================================================================================================
# Basic Segments (Directory, Mode, Time)
# ==================================================================================================

use ../format.nu [dim paint]

export def input-cwd [input: record]: nothing -> string {
  $input.workspace?.current_dir?
  | default --empty ($input.cwd? | default "")
}

export def format-dir [input: record, home: string = ""]: nothing -> string {
  let cwd = (input-cwd $input)
  if ($cwd | is-empty) {
    return ""
  }
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
  paint $label "blue_bold"
}

export def format-mode [input: record]: nothing -> string {
  let mode = ($input.vim?.mode? | default "" | into string | str trim)
  if ($mode | is-empty) {
    ""
  } else {
    paint $mode "magenta"
  }
}

export def format-time [now?: datetime]: nothing -> string {
  let timestamp = ($now | default (date now))
  dim ($timestamp | format date "%H:%M")
}
