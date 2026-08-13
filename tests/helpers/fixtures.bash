# Shared bats helpers. Loaded with: load helpers/fixtures

CT_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CT_REPO

# Source the library under test into the current shell.
ct_load_lib() {
  # shellcheck source=/dev/null
  source "$CT_REPO/bin/ct-lib.sh"
}

# Give the calling test its own tmux server so it never touches live sessions.
# Must be called from setup(), before any tmux invocation.
ct_isolate_tmux() {
  export TMUX_TMPDIR="$1/tmux"
  mkdir -p "$TMUX_TMPDIR"
}
