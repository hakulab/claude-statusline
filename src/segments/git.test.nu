#!/usr/bin/env nu

# ==================================================================================================
# Git Segment Formatting Tests
# ==================================================================================================

use std/assert
use ../theme.nu [resolve-theme]
use ./git.nu [format-git-info parse-branch work-counts]

def "test parse-branch handles tracking, unborn, detached, and invalid headers" [] {
  assert equal (parse-branch "## main...origin/main [ahead 2, behind 1]") {
    branch: "main"
    ahead: 2
    behind: 1
  }
  assert equal (parse-branch "## No commits yet on feat/init") {
    branch: "feat/init"
    ahead: 0
    behind: 0
  }
  assert equal (parse-branch "## HEAD (no branch)") {
    branch: ""
    ahead: 0
    behind: 0
  }
  assert equal (parse-branch "") {
    branch: ""
    ahead: 0
    behind: 0
  }
}

def "test work-counts tallies staged, modified, and untracked entries" [] {
  let entries = [
    "M  src/main.nu"
    "A  src/new.nu"
    "D  src/deleted.nu"
    "R  src/old.nu -> src/renamed.nu"
    "C  src/copy.nu"
    "MM src/both.nu"
    "AM src/added-then-edited.nu"
    " M README.md"
    " D removed-worktree.txt"
    " T symlink.txt"
    "?? scratch.txt"
    "?? notes.txt"
    "!! ignored.log"
  ]
  assert equal (work-counts $entries) {
    staged: 7
    modified: 5
    untracked: 2
  }
}

def "test format-git-info renders clean repo, dirty marks, and omits non-git dirs" [] {
  let repo = (mktemp --directory)
  ^git -C $repo init --initial-branch=main | complete | ignore
  ^git -C $repo config user.name "Test" | complete | ignore
  ^git -C $repo config user.email "test@example.com" | complete | ignore
  "hello\n" | save ($repo | path join "tracked.txt")
  ^git -C $repo add "tracked.txt" | complete | ignore
  ^git -C $repo commit -m "init" | complete | ignore

  let clean = (format-git-info $repo)
  assert equal ($clean | ansi strip) "main"
  assert not ($clean | str contains (ansi yellow))

  "changed\n" | save --force ($repo | path join "tracked.txt")
  "staged\n" | save ($repo | path join "staged.txt")
  ^git -C $repo add "staged.txt" | complete | ignore
  "new\n" | save ($repo | path join "untracked.txt")

  assert equal (format-git-info $repo | ansi strip) "main +1 !1 ?1"

  let latte = (resolve-theme {preset: "catppuccin-latte"}).theme
  let plain = (resolve-theme {} {NO_COLOR: "1"}).theme
  let styled = (format-git-info $repo --theme $latte)
  assert ($styled | str contains $latte.success)
  assert ($styled | str contains $latte.warning)
  assert equal (format-git-info $repo --theme $plain) "main +1 !1 ?1"

  let non_git = (mktemp --directory)
  assert equal (format-git-info $non_git) ""
  assert equal (format-git-info "") ""
}
