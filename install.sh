#!/bin/bash
# install.sh — Symlink liang-tdd skill into ~/.claude/
#
# Creates directory junctions (Windows) or symlinks (Unix) from
# ~/.claude/ into this repo so Claude Code discovers the skill.
#
# Usage:
#   bash install.sh              Install (create symlinks)
#   bash install.sh --uninstall  Remove symlinks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# Targets to link: source (in repo) -> destination (in ~/.claude/)
# Format: "repo_path|claude_path"
LINKS=(
  "commands/liang-tdd|commands/liang-tdd"
  "liang-tdd|liang-tdd"
  "hooks/tdd-test-guard.js|hooks/tdd-test-guard.js"
)

uninstall() {
  echo "Uninstalling liang-tdd skill..."
  for entry in "${LINKS[@]}"; do
    local target="${CLAUDE_DIR}/${entry#*|}"
    if [[ -L "$target" || -d "$target" ]]; then
      rm -rf "$target" 2>/dev/null || true
      echo "  Removed: $target"
    fi
  done
  echo "Done."
}

install() {
  echo "Installing liang-tdd skill..."
  echo "  Repo:   $SCRIPT_DIR"
  echo "  Claude: $CLAUDE_DIR"
  echo ""

  for entry in "${LINKS[@]}"; do
    local src="${entry%|*}"
    local dst="${entry#*|}"
    local full_src="$SCRIPT_DIR/$src"
    local full_dst="$CLAUDE_DIR/$dst"

    # Ensure parent directory exists
    mkdir -p "$(dirname "$full_dst")"

    # Remove existing target (backup if it's a real directory, not a link)
    if [[ -e "$full_dst" && ! -L "$full_dst" ]]; then
      local backup="${full_dst}.bak.$(date +%s)"
      echo "  Backing up existing: $full_dst -> $backup"
      mv "$full_dst" "$backup"
    elif [[ -L "$full_dst" ]]; then
      rm -f "$full_dst"
    fi

    # Create symlink/junction
    if [[ -d "$full_src" ]]; then
      # Directory: use junction on Windows (works without admin), symlink on Unix
      if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        # Convert to Windows paths for cmd /c mklink
        local win_src
        win_src=$(cygpath -w "$full_src" 2>/dev/null || echo "$full_src" | sed 's|/|\\|g')
        local win_dst
        win_dst=$(cygpath -w "$full_dst" 2>/dev/null || echo "$full_dst" | sed 's|/|\\|g')
        cmd //c "mklink /J \"$win_dst\" \"$win_src\"" > /dev/null 2>&1
      else
        ln -s "$full_src" "$full_dst"
      fi
      echo "  Linked: $dst -> $src (directory)"
    else
      # File: symlink (or copy on Windows if symlinks need admin)
      if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        local win_src
        win_src=$(cygpath -w "$full_src" 2>/dev/null || echo "$full_src" | sed 's|/|\\|g')
        local win_dst
        win_dst=$(cygpath -w "$full_dst" 2>/dev/null || echo "$full_dst" | sed 's|/|\\|g')
        # Try symlink first, fall back to hard link, then copy
        cmd //c "mklink \"$win_dst\" \"$win_src\"" > /dev/null 2>&1 || \
        cmd //c "mklink /H \"$win_dst\" \"$win_src\"" > /dev/null 2>&1 || \
        cp "$full_src" "$full_dst"
      else
        ln -s "$full_src" "$full_dst"
      fi
      echo "  Linked: $dst -> $src (file)"
    fi
  done

  echo ""
  echo "Installation complete. Run /liang-tdd:help to verify."
}

# --- Main ---
case "${1:-}" in
  --uninstall) uninstall ;;
  *)           install ;;
esac
