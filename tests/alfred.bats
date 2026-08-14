#!/usr/bin/env bats
#
# ct-alfred emits Alfred Script Filter JSON. Every subcommand here is pure
# output: it reads stubs on PATH and writes JSON, and touches nothing else.

load helpers/fixtures

setup() {
  CT_TMP="$(mktemp -d)"
  CT_STUBS="$CT_TMP/stubs"
  mkdir -p "$CT_STUBS"
  PATH="$CT_STUBS:$CT_REPO/bin:$PATH"
  export PATH
  export CT_STATE_DIR="$CT_TMP/state"
  export HOME="$CT_TMP/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$CT_TMP"
}

# Write an executable stub that prints $2 and exits $3 (default 0).
ct_stub() {
  cat > "$CT_STUBS/$1" <<EOF
#!/usr/bin/env bash
cat <<'STUBEOF'
$2
STUBEOF
exit ${3:-0}
EOF
  chmod +x "$CT_STUBS/$1"
}

@test "an unknown subcommand exits 2" {
  run ct-alfred no-such-thing
  [ "$status" -eq 2 ]
}

@test "a missing subcommand exits 2" {
  run ct-alfred
  [ "$status" -eq 2 ]
}

@test "switch-list turns tasks into Alfred rows" {
  ct_stub ct '[{"slug":"task-a","repo":"/r/myrepo","branch":"br-a","live":"worktree"}]'
  run ct-alfred switch-list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.items[0].title')" = "task-a" ]
  [ "$(echo "$output" | jq -r '.items[0].arg')" = "task-a" ]
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "true" ]
  [ "$(echo "$output" | jq -r '.items[0].subtitle')" != "" ]
}

@test "switch-list offers finish on the cmd modifier" {
  ct_stub ct '[{"slug":"task-a","repo":"/r/myrepo","branch":"br-a","live":"worktree"}]'
  run ct-alfred switch-list
  [ "$(echo "$output" | jq -r '.items[0].mods.cmd.arg')" = "task-a" ]
  [ "$(echo "$output" | jq -r '.items[0].mods.cmd.subtitle')" != "" ]
}

@test "switch-list shows a row rather than an empty list when there are no tasks" {
  ct_stub ct '[]'
  run ct-alfred switch-list
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.items | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
  [ "$(echo "$output" | jq -r '.items[0].title')" = "No tasks yet" ]
}

@test "switch-list reports a failing ct as a row, not as broken JSON" {
  ct_stub ct 'boom' 1
  run ct-alfred switch-list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}
