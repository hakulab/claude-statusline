#!/usr/bin/env nu

# ==================================================================================================
# Basic Segment Formatting Tests
# ==================================================================================================

use std/assert
use ../theme.nu [resolve-theme]
use ./basic.nu [format-dir format-mode format-time]

def "test format-dir renders basename, home tilde, root, cwd fallback, and omits empty cwd" [] {
  let cases = [
    {
      name: "workspace basename"
      input: {workspace: {current_dir: "/tmp/my-project"}}
      expected: "my-project"
    }
    {
      name: "home tilde"
      input: {workspace: {current_dir: "/home/user"}}
      expected: "~"
    }
    {
      name: "root directory"
      input: {workspace: {current_dir: "/"}}
      expected: "/"
    }
    {
      name: "cwd fallback"
      input: {cwd: "/tmp/fallback"}
      expected: "fallback"
    }
    {
      name: "empty cwd omitted"
      input: {}
      expected: ""
    }
  ]
  for case in $cases {
    let rendered = (format-dir $case.input "/home/user")
    let actual = if $case.expected == "" { $rendered } else { $rendered | ansi strip }
    assert equal $actual $case.expected $case.name
  }
}

def "test format-mode renders vim mode and omits missing or blank values" [] {
  assert equal (format-mode {vim: {mode: "NORMAL"}} | ansi strip) "NORMAL"
  assert equal (format-mode {vim: {mode: " INSERT "}} | ansi strip) "INSERT"
  assert equal (format-mode {vim: {mode: "   "}}) ""
  assert equal (format-mode {}) ""
}

def "test format-time formats HH:MM" [] {
  let dt = ("2026-11-26T14:35:00Z" | into datetime)
  assert equal (format-time $dt | ansi strip) "14:35"
}

def "test basic segments apply custom and empty themes" [] {
  let latte = (resolve-theme {preset: "catppuccin-latte"}).theme
  let plain = (resolve-theme {} {NO_COLOR: "1"}).theme
  let dt = ("2026-11-26T14:35:00Z" | into datetime)
  let dir_in = {workspace: {current_dir: "/tmp/app"}}

  assert (format-dir $dir_in "/home/u" --theme $latte | str contains $latte.accent)
  assert equal (format-dir $dir_in "/home/u" --theme $plain) "app"
  assert (format-mode {vim: {mode: "NORMAL"}} --theme $latte | str contains $latte.mode)
  assert equal (format-mode {vim: {mode: "NORMAL"}} --theme $plain) "NORMAL"
  assert (format-time $dt --theme $latte | str contains $latte.muted)
  assert equal (format-time $dt --theme $plain) "14:35"
}
