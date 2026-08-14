#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"

  # -b trunk is required: a bare repo's HEAD never migrates to the first
  # pushed branch, so without it HEAD stays at init.defaultBranch (main here),
  # the clone warns "remote HEAD refers to nonexistent ref" and sets no
  # refs/remotes/origin/HEAD, and ct_trunk_ref has nothing to derive from.
  git init -q -b trunk --bare "$CT_TMP/remote.git"

  git init -q -b trunk "$CT_TMP/seed"
  git -C "$CT_TMP/seed" config user.email t@example.com
  git -C "$CT_TMP/seed" config user.name Test
  echo hello > "$CT_TMP/seed/file.txt"
  git -C "$CT_TMP/seed" add -A
  git -C "$CT_TMP/seed" commit -q -m init
  git -C "$CT_TMP/seed" remote add origin "$CT_TMP/remote.git"
  git -C "$CT_TMP/seed" push -q origin trunk

  mkdir -p "$CT_TMP/roots"
  git clone -q "$CT_TMP/remote.git" "$CT_TMP/roots/myrepo"
  git -C "$CT_TMP/roots/myrepo" config user.email t@example.com
  git -C "$CT_TMP/roots/myrepo" config user.name Test
  CT_R="$CT_TMP/roots/myrepo"
}

teardown() {
  rm -rf "$CT_TMP"
}

@test "trunk_ref derives the default branch from origin HEAD" {
  run ct_trunk_ref "$CT_R"
  [ "$status" -eq 0 ]
  [ "$output" = "origin/trunk" ]
}

@test "branch_state reports none for an unknown slug" {
  run ct_branch_state "$CT_R" "nothing-here"
  [ "$output" = "none" ]
}

@test "branch_state reports local for an existing local branch" {
  git -C "$CT_R" branch mytask
  run ct_branch_state "$CT_R" "mytask"
  [ "$output" = "local" ]
}

@test "branch_state reports remote for a remote-only branch" {
  git -C "$CT_TMP/seed" branch remote-task
  git -C "$CT_TMP/seed" push -q origin remote-task
  git -C "$CT_R" fetch -q origin
  run ct_branch_state "$CT_R" "remote-task"
  [ "$output" = "remote" ]
}

@test "add_worktree creates a new branch off trunk" {
  run ct_add_worktree "$CT_R" "fresh-task"
  [ "$status" -eq 0 ]
  [ -e "$CT_TMP/roots/myrepo-wt/fresh-task/file.txt" ]
  run git -C "$CT_TMP/roots/myrepo-wt/fresh-task" rev-parse --abbrev-ref HEAD
  [ "$output" = "fresh-task" ]
}

@test "add_worktree reuses an existing local branch" {
  git -C "$CT_R" branch reuse-task
  run ct_add_worktree "$CT_R" "reuse-task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"local branch"* ]]
  run git -C "$CT_TMP/roots/myrepo-wt/reuse-task" rev-parse --abbrev-ref HEAD
  [ "$output" = "reuse-task" ]
}

@test "add_worktree tracks a remote-only branch" {
  git -C "$CT_TMP/seed" branch tracked-task
  git -C "$CT_TMP/seed" push -q origin tracked-task
  run ct_add_worktree "$CT_R" "tracked-task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"origin"* ]]
  run git -C "$CT_TMP/roots/myrepo-wt/tracked-task" rev-parse --abbrev-ref HEAD
  [ "$output" = "tracked-task" ]
}
