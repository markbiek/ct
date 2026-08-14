#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"
  export CT_CLAUDE_HOME="$CT_TMP/claude"
}

teardown() {
  rm -rf "$CT_TMP"
}

@test "project_dir escapes slashes" {
  run ct_claude_project_dir "/home/u/dev/myrepo"
  [ "$output" = "$CT_CLAUDE_HOME/projects/-home-u-dev-myrepo" ]
}

@test "project_dir escapes dots" {
  run ct_claude_project_dir "/home/u/.cache/thing"
  [ "$output" = "$CT_CLAUDE_HOME/projects/-home-u--cache-thing" ]
}

@test "claude_cmd is bare claude with no history" {
  run ct_claude_cmd "/home/u/dev/myrepo"
  [ "$output" = "claude" ]
}

@test "claude_cmd is claude --continue when history exists" {
  mkdir -p "$CT_CLAUDE_HOME/projects/-home-u-dev-myrepo"
  touch "$CT_CLAUDE_HOME/projects/-home-u-dev-myrepo/session.jsonl"
  run ct_claude_cmd "/home/u/dev/myrepo"
  [ "$output" = "claude --continue" ]
}

@test "claude_cmd is bare claude when the history dir is empty" {
  mkdir -p "$CT_CLAUDE_HOME/projects/-home-u-dev-myrepo"
  run ct_claude_cmd "/home/u/dev/myrepo"
  [ "$output" = "claude" ]
}
