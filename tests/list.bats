#!/usr/bin/env bats

load helpers/fixtures

setup() { ct_load_lib; }

@test "join_task_state marks a worktree with no session or workspace" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_join_task_state \
    <(printf '/r/myrepo-wt/task-a\tbranch-a\n') \
    <(printf '') \
    <(printf '')"
  [ "$output" = "$(printf 'task-a\t/r/myrepo\tbranch-a\tworktree')" ]
}

@test "join_task_state marks tmux and cmux when both are live" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_join_task_state \
    <(printf '/r/myrepo-wt/task-a\tbranch-a\n') \
    <(printf 'task-a\t/r/myrepo-wt/task-a\n') \
    <(printf 'workspace:3\ttask-a\n')"
  [ "$output" = "$(printf 'task-a\t/r/myrepo\tbranch-a\tworktree/tmux/cmux')" ]
}

@test "join_task_state ignores worktrees outside a -wt directory" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_join_task_state \
    <(printf '/r/myrepo\tmain\n') \
    <(printf '') \
    <(printf '')"
  [ "$output" = "" ]
}
