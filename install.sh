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

for name in ct ct-lib.sh ct-linear tms; do
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

echo "Installed to $bin_dir and $tmux_start"
