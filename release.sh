#!/usr/bin/env bash
# Cut a release: builds are archived under releases/vX.Y.Z/ permanently.
# Usage:
#   ./release.sh            release the version currently in VERSION
#   ./release.sh 0.4.0      bump VERSION to 0.4.0 and release it
#
# Release folders are never overwritten — bump VERSION for every new build
# you want to keep. Old versions are never deleted.
#
# Packaging (FOMOD retired in v0.12): ONE flat main package built from
# MRO-nofomod/ (everything MCM-managed at runtime), plus a separate optional
# zip for the rebalanced Experience.ini so a plain install can never clobber
# a user's Experience settings.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ge 1 ]]; then
    echo "$1" > VERSION
fi
VER="$(cat VERSION)"
DEST="releases/v${VER}"

if [[ -e "$DEST" ]]; then
    echo "ERROR: $DEST already exists. Releases are immutable — bump VERSION." >&2
    exit 1
fi

# Every release ships with its changelog entry — enforced mechanically because
# the convention was silently skipped once (v0.9.12, backfilled after the fact).
if ! grep -q "^## v${VER}" CHANGELOG.md; then
    echo "ERROR: CHANGELOG.md has no '## v${VER}' entry. Write the changelog first." >&2
    exit 1
fi

# Stamp version into the MCM and recompile all scripts
sed -i "s/MRO_VERSION = \"[^\"]*\"/MRO_VERSION = \"${VER}\"/" Source/Scripts/MRO_MCM.psc
sed -i "s/Marth Resurgence Overhaul v[0-9.]*/Marth Resurgence Overhaul v${VER}/" MRO_GenerateESP.py
tools/compile.sh all

# Regenerate ESP + SEQ into the package tree
python3 MRO_GenerateESP.py MRO-nofomod/

rm -f "MRO-v${VER}.zip" "MRO-ExperienceINI-v${VER}.zip"
(cd MRO-nofomod && zip -rq "../MRO-v${VER}.zip" .)
(cd Optional    && zip -q "../MRO-ExperienceINI-v${VER}.zip" Experience.ini)

mkdir -p "$DEST"
cp "MRO-v${VER}.zip" "MRO-ExperienceINI-v${VER}.zip" "$DEST/"

# Tag if this is a git repo with a clean-enough state
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add -A
    git commit -m "Release v${VER}" || true
    git tag "v${VER}"   # fails if the tag exists — tags are immutable too
fi

echo "Released v${VER} -> $DEST/"
