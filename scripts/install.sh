#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--target agents|claude|codex] [--name zread]

Install this skill into a global skills directory.

Targets:
  agents  ~/.agents/skills              (Multica/Codex workspaces)
  claude  ~/.claude/skills              (Claude Code)
  codex   $CODEX_HOME/skills or ~/.codex/skills
USAGE
}

target="agents"
name="zread"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      target="${2:?missing target}"
      shift 2
      ;;
    --name)
      name="${2:?missing name}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$target" in
  agents)
    root="$HOME/.agents/skills"
    ;;
  claude)
    root="$HOME/.claude/skills"
    ;;
  codex)
    root="${CODEX_HOME:-$HOME/.codex}/skills"
    ;;
  *)
    echo "unknown target: $target" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/$name"

mkdir -p "$root"

if [ -e "$dest" ] && [ ! -d "$dest" ]; then
  echo "destination exists but is not a directory: $dest" >&2
  exit 1
fi

if [ -d "$dest/.git" ]; then
  echo "updating existing git checkout: $dest"
  git -C "$dest" fetch --all --prune
  git -C "$dest" reset --hard origin/main
elif [ -d "$dest" ]; then
  echo "replacing existing directory: $dest"
  rm -rf "$dest"
  cp -R "$repo_root" "$dest"
  rm -rf "$dest/.git"
else
  echo "installing to: $dest"
  cp -R "$repo_root" "$dest"
  rm -rf "$dest/.git"
fi

duplicates="$(find "$root" -maxdepth 2 -name SKILL.md -print0 \
  | xargs -0 awk '
      FNR == 1 { file = FILENAME; in_header = 0 }
      /^---$/ { in_header = !in_header; next }
      in_header && /^name:[[:space:]]*zread[[:space:]]*$/ { print file }
    ' \
  | sort)"

echo "installed: $dest"
if [ "$(printf '%s\n' "$duplicates" | sed '/^$/d' | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "warning: multiple skills declare name: zread under $root"
  printf '%s\n' "$duplicates"
fi

echo "restart or start a new agent session so the skill list is reloaded."
