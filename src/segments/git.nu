# ==================================================================================================
# Git Status Segment
# ==================================================================================================

use ../format.nu [paint]
use ../theme.nu [default-theme]

const NO_BRANCH = {
  branch: ""
  ahead: 0
  behind: 0
}

def git-status [cwd: string]: nothing -> list<string> {
  let result = (
    ^git
      -C $cwd
      --no-optional-locks
      status
        --porcelain
        --branch
    | complete
  )
  if $result.exit_code != 0 {
    return []
  }

  $result.stdout | lines
}

def track-count [track: string, label: string]: nothing -> int {
  $track | parse --regex ($label + ' (?<n>\d+)') | get -o 0.n | default "0" | into int
}

# `## <branch>...<upstream> [ahead N, behind M]`, where everything after the branch is optional. A
# detached HEAD reads `## HEAD (no branch)` and an unborn one `## No commits yet on <branch>`.
export def parse-branch [
  header: string
]: nothing -> record<branch: string, ahead: int, behind: int> {
  if $header == "## HEAD (no branch)" {
    return $NO_BRANCH
  }

  let parsed = (
    $header
    | parse --regex '^## (?:No commits yet on )?(?<branch>\S+?)(?:\.\.\.\S*)?(?: \[(?<track>[^\]]*)\])?$'
    | get -o 0
  )
  if $parsed == null {
    return $NO_BRANCH
  }

  {
    branch: $parsed.branch
    ahead: (track-count ($parsed.track | default "") "ahead")
    behind: (track-count ($parsed.track | default "") "behind")
  }
}

# Porcelain v1 XY codes: X is the index status, Y the worktree status.
export def work-counts [
  entries: list<string>
]: nothing -> record<staged: int, modified: int, untracked: int> {
  let codes = ($entries | each { str substring 0..<2 })
  let tracked = ($codes | where $it != "??" and $it != "!!")
  {
    staged: ($tracked | where ($it | str substring 0..<1) in ["M" "A" "D" "R" "C"] | length)
    modified: ($tracked | where ($it | str substring 1..<2) in ["M" "D" "T"] | length)
    untracked: ($codes | where $it == "??" | length)
  }
}

export def format-git-info [cwd: string, --theme: record]: nothing -> string {
  if ($cwd | is-empty) {
    return ""
  }
  let output = (git-status $cwd)
  let branch = (parse-branch ($output | first | default ""))
  if ($branch.branch | is-empty) {
    return ""
  }

  let t = ($theme | default (default-theme))
  let work = (work-counts ($output | skip 1))
  let marks = (
    [
      [symbol n];
      ["»" $branch.ahead]
      ["«" $branch.behind]
      ["+" $work.staged]
      ["!" $work.modified]
      ["?" $work.untracked]
    ]
    | where n > 0
    | each {|mark| $" ($mark.symbol)($mark.n)" }
    | str join
  )

  if ($marks | is-empty) {
    paint $branch.branch $t.success
  } else {
    $"(paint $branch.branch $t.success)(paint $marks $t.warning)"
  }
}
