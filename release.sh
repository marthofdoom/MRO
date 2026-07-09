#!/usr/bin/env bash
# Cut a release: builds are archived under releases/vX.Y.Z/ permanently.
# Usage:
#   ./release.sh            release the version currently in VERSION
#   ./release.sh 0.4.0      bump VERSION to 0.4.0 and release it
#
# Release folders are never overwritten — bump VERSION for every new build
# you want to keep. Old versions are never deleted.
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
sed -i "s/Marth Requiem Overhaul v[0-9.]*/Marth Requiem Overhaul v${VER}/" MRO_GenerateESP.py
# Stamp the FOMOD version so info.xml never drifts from the release
sed -i "s#<Version>[0-9.]*</Version>#<Version>${VER}</Version>#" MRO-flat/fomod/info.xml
tools/compile.sh all

# Regenerate ESP + SEQ into both package trees
python3 MRO_GenerateESP.py MRO-nofomod/
cp MRO-nofomod/MRO.esp MRO-flat/
mkdir -p MRO-flat/SEQ
cp MRO-nofomod/SEQ/MRO.seq MRO-flat/SEQ/

rm -f "MRO-test-nofomod.zip" "MRO-v${VER}.zip"
(cd MRO-nofomod && zip -rq "../MRO-test-nofomod.zip" .)
(cd MRO-flat    && zip -rq "../MRO-v${VER}.zip" .)

mkdir -p "$DEST"
cp "MRO-v${VER}.zip" "MRO-test-nofomod.zip" "$DEST/"

# Tag if this is a git repo with a clean-enough state
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add -A
    git commit -m "Release v${VER}" || true
    git tag "v${VER}"   # fails if the tag exists — tags are immutable too
fi

echo "Released v${VER} -> $DEST/"
