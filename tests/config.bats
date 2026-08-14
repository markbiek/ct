#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"
  export HOME="$CT_TMP/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$CT_TMP"
}

@test "load_config falls back to defaults with no config file" {
  ct_load_config
  [ "${CT_ROOTS[0]}" = "$HOME/dev" ]
  [ "${#CT_ROOTS[@]}" -eq 4 ]
}

@test "load_config lets the config file replace the defaults" {
  mkdir -p "$HOME/.config/ct"
  echo 'CT_ROOTS=("/one" "/two")' > "$HOME/.config/ct/config.sh"
  ct_load_config
  [ "${#CT_ROOTS[@]}" -eq 2 ]
  [ "${CT_ROOTS[0]}" = "/one" ]
  [ "${CT_ROOTS[1]}" = "/two" ]
}
