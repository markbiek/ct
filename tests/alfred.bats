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
