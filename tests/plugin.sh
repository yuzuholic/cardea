#!/bin/sh
# the cardea marketplace and plugin are valid, and every skill and agent declares itself.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }

claude plugin validate . >/dev/null || fail "marketplace does not validate"
claude plugin validate plugins/cardea >/dev/null || fail "plugin does not validate"

for skill in plugins/cardea/skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$skill")")
  head -1 "$skill" | grep -qx -- '---' || fail "$skill: no frontmatter"
  grep -qx "name: $dir" "$skill" || fail "$skill: name is not '$dir'"
  grep -q '^description: ..' "$skill" || fail "$skill: no description"
done

for agent in plugins/cardea/agents/*.md; do
  name=$(basename "$agent" .md)
  grep -qx "name: $name" "$agent" || fail "$agent: name is not '$name'"
  grep -q '^description: ..' "$agent" || fail "$agent: no description"
done

echo "ok: plugin, $(ls plugins/cardea/skills | wc -l | tr -d ' ') skills, $(ls plugins/cardea/agents | wc -l | tr -d ' ') agents"
