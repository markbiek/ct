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

# A scratch tree of two repos, wired into CT_ROOTS through a throwaway HOME.
ct_repos_fixture() {
  mkdir -p "$CT_TMP/roots/myrepo/.git" "$CT_TMP/roots/other/.git"
  mkdir -p "$HOME/.config/ct"
  cat > "$HOME/.config/ct/config.sh" <<EOF
CT_ROOTS=("$CT_TMP/roots")
EOF
}

@test "new-list lists repos before the delimiter" {
  ct_repos_fixture
  run ct-alfred new-list ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.items | length')" = "2" ]
  [ "$(echo "$output" | jq -r '[.items[].title] | sort | join(",")')" = "myrepo,other" ]
}

@test "new-list repo rows autocomplete the delimiter instead of acting" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo"
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
  [ "$(echo "$output" | jq -r '.items[0].autocomplete')" = "myrepo > " ]
}

@test "new-list filters repos by the typed text" {
  ct_repos_fixture
  run ct-alfred new-list "oth"
  [ "$(echo "$output" | jq -r '.items | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[0].title')" = "other" ]
}

@test "new-list says so when no repo matches" {
  ct_repos_fixture
  run ct-alfred new-list "zzz"
  [ "$(echo "$output" | jq -r '.items | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}

@test "new-list normalizes the typed name into a slug" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo > ABC-857 Autofix"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "true" ]
  [ "$(echo "$output" | jq -r '.items[0].title')" = "Create abc-857-autofix" ]
  # printf, not a literal tab: an invisible tab in a test file is a trap.
  [ "$(echo "$output" | jq -r '.items[0].arg')" \
    = "$(printf '%s/roots/myrepo\tabc-857-autofix' "$CT_TMP")" ]
}

@test "new-list flags a name it had to change" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo > ABC-857 Autofix"
  [[ "$(echo "$output" | jq -r '.items[0].subtitle')" == *"normalized"* ]]
}

@test "new-list leaves an already-valid slug alone and says nothing about it" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo > abc-857-autofix"
  [ "$(echo "$output" | jq -r '.items[0].title')" = "Create abc-857-autofix" ]
  [[ "$(echo "$output" | jq -r '.items[0].subtitle')" != *"normalized"* ]]
}

@test "new-list prompts rather than acting on an empty name" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo > "
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}

@test "new-list rejects a repo that does not exist" {
  ct_repos_fixture
  run ct-alfred new-list "nosuch > thing"
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}

@test "new-list prompts when the name is punctuation only" {
  ct_repos_fixture
  run ct-alfred new-list "myrepo > !!!"
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}

@test "linear-list turns issues into rows that prefill ctn" {
  ct_stub ct-linear "$(printf 'ABC-857\tUnderstand the thing')"
  mkdir -p "$CT_STATE_DIR"
  echo "/r/myrepo" > "$CT_STATE_DIR/recent"
  run ct-alfred linear-list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.items[0].title')" = "ABC-857" ]
  [ "$(echo "$output" | jq -r '.items[0].subtitle')" = "Understand the thing" ]
  [ "$(echo "$output" | jq -r '.items[0].arg')" = "myrepo > abc-857-" ]
}

@test "linear-list omits the repo half when there is no recent repo" {
  ct_stub ct-linear "$(printf 'ABC-857\tUnderstand the thing')"
  run ct-alfred linear-list
  [ "$(echo "$output" | jq -r '.items[0].arg')" = "abc-857-" ]
}

@test "linear-list explains a missing API key" {
  ct_stub ct-linear 'Error: no Linear API key found.' 1
  run ct-alfred linear-list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
  [[ "$(echo "$output" | jq -r '.items[0].subtitle')" == *"security add-generic-password"* ]]
}

@test "linear-list handles an empty issue list" {
  ct_stub ct-linear ''
  run ct-alfred linear-list
  [ "$(echo "$output" | jq -r '.items | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[0].valid')" = "false" ]
}
