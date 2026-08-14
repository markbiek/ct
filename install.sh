#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
bin_dir="${CT_BIN_DIR:-$HOME/.local/bin}"
config_dir="${CT_CONFIG_DIR:-$HOME/.config}"
tmux_start="$config_dir/tmux-start"

# A legacy tms install leaves this as a symlink into the tms repo; writing
# through it would silently modify that repo.
if [[ -L "$tmux_start" ]]; then
  echo "Error: $tmux_start is a symlink (legacy tms install)." >&2
  echo "Replace it with a real directory holding your config.sh and projects/ first." >&2
  exit 1
fi

# A real directory here would make `ln -sfn` nest the link inside it.
if [[ -d "$tmux_start/profiles" && ! -L "$tmux_start/profiles" ]]; then
  echo "Error: $tmux_start/profiles is a real directory. Move it aside first." >&2
  exit 1
fi

mkdir -p "$bin_dir" "$tmux_start/projects"

for name in ct ct-alfred ct-lib.sh ct-linear tms; do
  if [[ -e "$repo_dir/bin/$name" ]]; then
    ln -sfn "$repo_dir/bin/$name" "$bin_dir/$name"
  fi
done

# Shipped: always points at the repo.
ln -sfn "$repo_dir/tmux-start/profiles" "$tmux_start/profiles"

# Yours: seeded once, never overwritten.
if [[ ! -f "$tmux_start/config.sh" ]]; then
  cp "$repo_dir/tmux-start/config.sh.example" "$tmux_start/config.sh"
  echo "Seeded $tmux_start/config.sh"
fi
if [[ ! -e "$tmux_start/projects/example.sh" ]]; then
  cp "$repo_dir/tmux-start/projects/example.sh" "$tmux_start/projects/example.sh"
fi

# Alfred workflow. Optional: a machine without Alfred still gets a working ct.
alfred_workflow_dir() {
  if [[ -n "${CT_ALFRED_WORKFLOW_DIR:-}" ]]; then
    printf '%s' "$CT_ALFRED_WORKFLOW_DIR"
    return 0
  fi
  local sync
  # Alfred keeps its preferences in a sync folder when one is configured, and
  # the default directory is left empty in that case. Assuming the default
  # would install a workflow that Alfred never reads.
  sync="$(defaults read com.runningwithcrayons.Alfred-Preferences syncfolder 2>/dev/null)" || sync=""
  if [[ -n "$sync" ]]; then
    printf '%s/Alfred.alfredpreferences/workflows' "${sync/#\~/$HOME}"
    return 0
  fi
  printf '%s' "$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows"
}

wf_dir="$(alfred_workflow_dir)"
if [[ -d "$wf_dir" ]]; then
  mkdir -p "$wf_dir/ct-alfred"
  # Copy, not symlink: Alfred does not reliably follow a symlinked workflow.
  cp "$repo_dir/alfred/info.plist" "$wf_dir/ct-alfred/info.plist"
  echo "Installed the Alfred workflow to $wf_dir/ct-alfred"
else
  echo "Alfred workflow directory not found; skipping the workflow"
fi

echo "Installed to $bin_dir and $tmux_start"
