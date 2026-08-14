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

# A `ct` stub that records the major bash version it was actually invoked
# under (its own shebang is `env bash`, so this is exactly what a real `ct`
# would see).
ct_stub_bash_version_probe() {
  cat > "$CT_STUBS/ct" <<EOF
#!/usr/bin/env bash
printf '%s' "\$BASH_VERSINFO" > "$CT_TMP/ct-bash-major"
echo '[]'
EOF
  chmod +x "$CT_STUBS/ct"
}

@test "the re-exec prepends a modern bash so ct is found under it, not /bin/bash 3.2" {
  ct_stub_bash_version_probe
  # Simulate Alfred's bare environment: only the system PATH plus the stub
  # dir, and nothing else exported. ct-alfred's shebang is `env bash`, so with
  # this PATH env resolves it to /bin/bash 3.2 -- exactly what Alfred does.
  run env -i HOME="$HOME" PATH="/usr/bin:/bin:$CT_STUBS" "$CT_REPO/bin/ct-alfred" switch-list
  [ "$status" -eq 0 ]
  [ -f "$CT_TMP/ct-bash-major" ]
  [ "$(cat "$CT_TMP/ct-bash-major")" -ge 4 ]
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

@test "new-list says nothing about normalization for the ctl trailing-hyphen prefill" {
  ct_repos_fixture
  # This is exactly what linear-list hands back: an already-slugified
  # identifier plus a trailing hyphen inviting a suffix.
  run ct-alfred new-list "myrepo > abc-857-"
  [ "$(echo "$output" | jq -r '.items[0].title')" = "Create abc-857" ]
  [[ "$(echo "$output" | jq -r '.items[0].subtitle')" != *"normalized"* ]]
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

# Records its argv so the test can assert what ct was asked to do.
ct_recording_stub() {
  cat > "$CT_STUBS/ct" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CT_TMP/ct.log"
echo "${1:-ok}"
exit ${2:-0}
EOF
  chmod +x "$CT_STUBS/ct"
}

@test "do-switch calls ct switch with the slug" {
  ct_recording_stub
  run ct-alfred do-switch task-a
  [ "$status" -eq 0 ]
  [ "$(cat "$CT_TMP/ct.log")" = "switch task-a" ]
}

@test "do-finish calls ct finish with the slug" {
  ct_recording_stub
  run ct-alfred do-finish task-a
  [ "$status" -eq 0 ]
  [ "$(cat "$CT_TMP/ct.log")" = "finish task-a" ]
}

@test "do-new splits the tab-separated arg into repo and name" {
  ct_recording_stub
  run ct-alfred do-new "$(printf '/r/myrepo\tabc-857-autofix')"
  [ "$status" -eq 0 ]
  [ "$(cat "$CT_TMP/ct.log")" = "new --repo /r/myrepo --name abc-857-autofix" ]
}

@test "a failing ct still exits 0 and reports its message" {
  ct_recording_stub "worktree is dirty" 1
  run ct-alfred do-finish task-a
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree is dirty"* ]]
}

# Writes to stderr, unlike ct_recording_stub -- this is what a real ct
# refusal looks like, and is the only way to prove ct_alfred_run merges
# stderr rather than discarding it.
ct_stub_stderr() {
  printf '#!/usr/bin/env bash\necho "%s" >&2\nexit 1\n' "$1" > "$CT_STUBS/ct"
  chmod +x "$CT_STUBS/ct"
}

@test "do-finish surfaces a refusal ct wrote to stderr" {
  ct_stub_stderr "Error: task-a has unsaved work"
  run ct-alfred do-finish task-a
  [ "$status" -eq 0 ]
  [[ "$output" == *"unsaved work"* ]]
  # Without the 2>&1 merge, ct_alfred_run's local $out stays empty (stderr
  # bypasses the capture) and it falls back to "finished with no output" --
  # which bats' own combined stdout/stderr capture would otherwise mask, so
  # this is the assertion that actually pins the merge.
  [[ "$output" != *"finished with no output"* ]]
}

@test "do-switch refuses a missing slug rather than crashing" {
  ct_recording_stub
  run ct-alfred do-switch
  [ "$status" -eq 0 ]
  [[ "$output" == *"No task slug"* ]]
  [ ! -f "$CT_TMP/ct.log" ]
}

@test "do-finish refuses a missing slug rather than crashing" {
  ct_recording_stub
  run ct-alfred do-finish
  [ "$status" -eq 0 ]
  [[ "$output" == *"No task slug"* ]]
  [ ! -f "$CT_TMP/ct.log" ]
}

@test "do-new refuses a malformed arg" {
  ct_recording_stub
  run ct-alfred do-new "no-tab-here"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not read"* ]]
  [ ! -f "$CT_TMP/ct.log" ]
}
