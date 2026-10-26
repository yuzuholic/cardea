#!/bin/sh
# install the skills that herdr and graphify ship themselves, generated from the installed
# binaries so they always match the version on this machine. rerun after updating either.
#
#   scripts/vendor-skills.sh [skills dir]      default: ~/.claude/skills
#
# a tool that isn't installed is skipped, not an error. exits non-zero if a tool is
# installed but its skill could not be produced.
set -eu

DEST="${1:-$HOME/.claude/skills}"
mkdir -p "$DEST"
FAILED=

# herdr prints its official skill as a complete SKILL.md.
if command -v herdr >/dev/null 2>&1; then
  mkdir -p "$DEST/herdr"
  if herdr --skill > "$DEST/herdr/SKILL.md.tmp" && [ -s "$DEST/herdr/SKILL.md.tmp" ]; then
    mv "$DEST/herdr/SKILL.md.tmp" "$DEST/herdr/SKILL.md"
    echo "herdr skill → $DEST/herdr"
  else
    rm -f "$DEST/herdr/SKILL.md.tmp"
    echo "herdr: --skill produced nothing" >&2; FAILED=1
  fi
else
  echo "herdr: not installed, skipped"
fi

# graphify only writes its skill through `graphify install`, which also appends a block to
# CLAUDE.md. point it at a scratch config dir so the real CLAUDE.md (a link into this repo)
# is never touched, then keep only the skill folder.
if command -v graphify >/dev/null 2>&1; then
  scratch=$(mktemp -d)
  if CLAUDE_CONFIG_DIR="$scratch" graphify install >/dev/null 2>&1 && [ -s "$scratch/skills/graphify/SKILL.md" ]; then
    rm -rf "$DEST/graphify"
    mv "$scratch/skills/graphify" "$DEST/graphify"
    echo "graphify skill → $DEST/graphify"
  else
    echo "graphify: install did not produce a skill" >&2; FAILED=1
  fi
  rm -rf "$scratch"
else
  echo "graphify: not installed, skipped"
fi

[ -z "$FAILED" ]
