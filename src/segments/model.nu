# ==================================================================================================
# Model Name Segment
# ==================================================================================================

use ../format.nu [paint]
use ../theme.nu [default-theme]

export def model-name [input: record, models: record]: nothing -> string {
  let id = ($input.model?.id? | default "")
  let model_id = ($id | str replace --regex '(?i)\[1m\]$' "")
  let display_name = ($input.model?.display_name? | default $id | str trim)
  let fallback = if $display_name == $id {
    $model_id | split row "/" | last
  } else {
    $display_name | str replace "(1M context)" "(1M)"
  }
  let name = ($models | get -o $model_id | default $fallback)
  if ($name | is-empty) {
    return ""
  }

  let large_context = (
    ($input.context_window?.context_window_size? | default 0) >= 1000000
    or ($id | str lowercase | str ends-with "[1m]")
  )
  [
    $name
    (if $large_context and not ($name | str contains "(1M)") { "(1M)" })
    $input.effort?.level?
  ]
  | compact --empty
  | str join " "
}

export def format-model [input: record, models: record, --theme: record]: nothing -> string {
  let name = (model-name $input $models)
  if ($name | is-empty) {
    ""
  } else {
    let t = ($theme | default { default-theme })
    paint $name $t.info
  }
}
