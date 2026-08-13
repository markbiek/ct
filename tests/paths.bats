#!/usr/bin/env bats

load helpers/fixtures

setup() { ct_load_lib; }

@test "repo_name is the basename" {
  run ct_repo_name "/home/u/dev/myrepo"
  [ "$output" = "myrepo" ]
}

@test "repo_name ignores a trailing slash" {
  run ct_repo_name "/home/u/dev/myrepo/"
  [ "$output" = "myrepo" ]
}

@test "worktree_root is a sibling -wt directory" {
  run ct_worktree_root "/home/u/dev/myrepo"
  [ "$output" = "/home/u/dev/myrepo-wt" ]
}

@test "worktree_root works at any depth" {
  run ct_worktree_root "/home/u/src/org/other"
  [ "$output" = "/home/u/src/org/other-wt" ]
}

@test "worktree_path joins root and slug" {
  run ct_worktree_path "/home/u/dev/myrepo" "abc-700-autofix"
  [ "$output" = "/home/u/dev/myrepo-wt/abc-700-autofix" ]
}
