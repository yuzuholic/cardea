#!/bin/sh
# install the skills that herdr, graphify, playwright-cli, marimo and langfuse ship themselves.
# herdr's, graphify's and playwright-cli's are generated from the installed binaries so they match
# the version on this machine; marimo's notebook skill and langfuse's skill are copied from their skills repos.
# rerun after updating any of them.
#
#   scripts/vendor-skills.sh [skills dir [skill...]]      default: ~/.claude/skills, every skill
#
# naming skills (herdr, graphify, playwright-cli, marimo-notebook, langfuse) makes only those
# run, so the installer can start each as soon as its tool is there.
#
# a tool that isn't installed is skipped, not an error. exits non-zero if a tool is
# installed but its skill could not be produced.
set -eu

DEST="${1:-$HOME/.claude/skills}"
[ $# -eq 0 ] || shift
mkdir -p "$DEST"
FAILED=
SKILLS=" $* "

want() { [ "$SKILLS" = '  ' ] || case "$SKILLS" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# herdr prints its official skill as a complete SKILL.md.
if want herdr; then
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
fi

# graphify only writes its skill through `graphify install`, which also appends a block to
# CLAUDE.md. point it at a scratch config dir so the real CLAUDE.md (a link into this repo)
# is never touched, then keep only the skill folder.
if want graphify; then
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
fi

# playwright-cli writes its skill under the home directory, so give it a scratch home.
if want playwright-cli; then
  if command -v playwright-cli >/dev/null 2>&1; then
    scratch=$(mktemp -d)
    if HOME="$scratch" playwright-cli install --skills claude --global >/dev/null 2>&1 && [ -s "$scratch/.claude/skills/playwright-cli/SKILL.md" ]; then
      rm -rf "$DEST/playwright-cli"
      mv "$scratch/.claude/skills/playwright-cli" "$DEST/playwright-cli"
      echo "playwright-cli skill → $DEST/playwright-cli"
    else
      echo "playwright-cli: install did not produce a skill" >&2; FAILED=1
    fi
    rm -rf "$scratch"
  else
    echo "playwright-cli: not installed, skipped"
  fi
fi

# marimo publishes its skills in a git repo rather than a binary, so take the latest
# marimo-notebook folder from it.
if want marimo-notebook; then
  scratch=$(mktemp -d)
  if git clone -q --depth 1 https://github.com/marimo-team/skills "$scratch/repo" 2>/dev/null &&
     [ -s "$scratch/repo/skills/marimo-notebook/SKILL.md" ]; then
    rm -rf "$DEST/marimo-notebook"
    mv "$scratch/repo/skills/marimo-notebook" "$DEST/marimo-notebook"
    echo "marimo-notebook skill → $DEST/marimo-notebook"
  else
    echo "marimo: could not fetch marimo-team/skills" >&2; FAILED=1
  fi
  rm -rf "$scratch"
fi

# langfuse publishes its skill the same way; the folder carries a references/ directory too.
if want langfuse; then
  scratch=$(mktemp -d)
  if git clone -q --depth 1 https://github.com/langfuse/skills "$scratch/repo" 2>/dev/null &&
     [ -s "$scratch/repo/skills/langfuse/SKILL.md" ]; then
    rm -rf "$DEST/langfuse"
    mv "$scratch/repo/skills/langfuse" "$DEST/langfuse"
    echo "langfuse skill → $DEST/langfuse"
  else
    echo "langfuse: could not fetch langfuse/skills" >&2; FAILED=1
  fi
  rm -rf "$scratch"
fi

[ -z "$FAILED" ]
