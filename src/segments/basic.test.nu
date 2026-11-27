#!/usr/bin/env nu

# ==================================================================================================
# Basic Segment Formatting Tests
# ==================================================================================================

use std/assert
use ./basic.nu [format-dir format-mode format-time]

def "test format-dir renders basename, home tilde, root, cwd fallback, and omits empty cwd" [] {
  let dir_in = {workspace: {current_dir: "/tmp/my-project"}}
  assert equal (format-dir $dir_in "/home/user" | ansi strip) "my-project"
  assert equal (format-dir {workspace: {current_dir: "/home/user"}} "/home/user" | ansi strip) "~"
  assert equal (format-dir {workspace: {current_dir: "/"}} "/home/user" | ansi strip) "/"
  assert equal (format-dir {cwd: "/tmp/fallback"} "/home/user" | ansi strip) "fallback"
  assert equal (format-dir {} "/home/user") ""
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
