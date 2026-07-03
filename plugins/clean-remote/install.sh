#!/bin/sh
# clean-remote — manual (no-plugin) installer.
#
# Installs the clean-remote skills as plain *project skills* into a target repo, instead
# of through the Claude Code plugin marketplace. It copies the skills and their
# scripts, then rewrites the `${CLAUDE_PLUGIN_ROOT}` reference in each SKILL.md —
# that variable only resolves under the plugin loader, so a bare copy (or a copy
# fetched by a skills installer such as `npx skills install`) would otherwise run
# `sh "/scripts/setup.sh"` and fail. The rewrite points at an absolute path to the
# copied scripts, so the skills work regardless of which directory Claude runs from.
#
# Usage:
#   sh install.sh <target-project-dir>
#
# Re-runnable: re-running overwrites the installed copies in place. To remove,
# delete the two directories printed at the end (and, in the target repo, run the
# `uninstall` skill first if you had already run `setup` there).

set -eu

SKILLS='setup target publish scrub-refs sync doctor uninstall'

# --- locate this repo, so the installer works from any working directory -----
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src_skills="$here/skills"
src_scripts="$here/scripts"

if [ ! -d "$src_skills" ] || [ ! -d "$src_scripts" ]; then
  echo "error: expected skills/ and scripts/ next to install.sh (looked in $here)" >&2
  exit 1
fi

# --- resolve the target project ---------------------------------------------
if [ "$#" -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "usage: sh install.sh <target-project-dir>" >&2
  exit 2
fi
target=$(CDPATH= cd -- "$1" 2>/dev/null && pwd) || {
  echo "error: target directory not found: $1" >&2
  exit 2
}

dst_skills="$target/.claude/skills"
dst_scripts="$target/.claude/clean-remote-scripts"

mkdir -p "$dst_skills" "$dst_scripts"

# --- copy the scripts to one shared location in the target -------------------
# *.sh covers every skill entrypoint plus lib.sh; pre-push is copied by setup.sh.
cp "$src_scripts"/*.sh "$src_scripts/pre-push" "$dst_scripts/"

# --- copy each skill and rewrite the plugin-root reference -------------------
# Escape the replacement path for sed (\, the # delimiter, and &).
esc=$(printf '%s' "$dst_scripts/" | sed 's/[\\#&]/\\&/g')

for s in $SKILLS; do
  if [ ! -f "$src_skills/$s/SKILL.md" ]; then
    echo "error: missing source skill: $src_skills/$s/SKILL.md" >&2
    exit 1
  fi
  mkdir -p "$dst_skills/$s"
  # \${CLAUDE_PLUGIN_ROOT} is escaped so the *installer's* shell does not expand it.
  sed "s#\${CLAUDE_PLUGIN_ROOT}/scripts/#${esc}#g" \
    "$src_skills/$s/SKILL.md" > "$dst_skills/$s/SKILL.md"
done

echo "Installed clean-remote (manual mode) into: $target"
echo "  skills : $dst_skills/{$(echo "$SKILLS" | tr ' ' ',')}/SKILL.md"
echo "  scripts: $dst_scripts/"
echo
echo "These load as un-namespaced project skills: setup, target, publish, scrub-refs, sync, doctor, uninstall."
echo "Next: open Claude Code in the target project and run the 'setup' skill."
echo
echo "Note: the rewritten paths are absolute. If you move the target project,"
echo "re-run this installer to refresh them."
