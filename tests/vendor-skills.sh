#!/bin/sh
# scripts/vendor-skills.sh produces the herdr, graphify, playwright-cli, marimo-notebook and langfuse skills,
# and never touches the real CLAUDE.md while doing it. needs herdr, graphify and playwright-cli installed, and
# network.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v herdr >/dev/null || fail "herdr is not installed"
command -v graphify >/dev/null || fail "graphify is not installed"
command -v playwright-cli >/dev/null || fail "playwright-cli is not installed"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/.claude"
echo "sentinel" > "$work/home/.claude/CLAUDE.md"

HOME="$work/home" sh scripts/vendor-skills.sh "$work/skills" || fail "vendor-skills.sh exited non-zero"

grep -qx 'name: herdr' "$work/skills/herdr/SKILL.md" || fail "herdr skill missing or misnamed"
grep -qx 'name: graphify' "$work/skills/graphify/SKILL.md" || fail "graphify skill missing or misnamed"
grep -qx 'name: playwright-cli' "$work/skills/playwright-cli/SKILL.md" || fail "playwright-cli skill missing or misnamed"
grep -qx 'name: marimo-notebook' "$work/skills/marimo-notebook/SKILL.md" || fail "marimo-notebook skill missing or misnamed"
grep -qx 'name: langfuse' "$work/skills/langfuse/SKILL.md" || fail "langfuse skill missing or misnamed"
[ "$(cat "$work/home/.claude/CLAUDE.md")" = sentinel ] || fail "graphify edited the real CLAUDE.md"

# a second run replaces cleanly instead of nesting or failing
HOME="$work/home" sh scripts/vendor-skills.sh "$work/skills" >/dev/null || fail "second run failed"
[ ! -d "$work/skills/graphify/graphify" ] || fail "second run nested the graphify folder"
[ ! -d "$work/skills/playwright-cli/playwright-cli" ] || fail "second run nested the playwright-cli folder"
[ ! -d "$work/skills/marimo-notebook/marimo-notebook" ] || fail "second run nested the marimo-notebook folder"
[ ! -d "$work/skills/langfuse/langfuse" ] || fail "second run nested the langfuse folder"

echo "ok: herdr, graphify, playwright-cli, marimo-notebook and langfuse skills generated"
