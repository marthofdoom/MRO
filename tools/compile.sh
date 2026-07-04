#!/usr/bin/env bash
# Compile Papyrus scripts and copy the .pex into both package trees.
# Usage: tools/compile.sh MRO_StartupQuest [MRO_MCM ...]   (no .psc suffix)
#        tools/compile.sh all
# Requires no other context: all paths are baked in for this machine.
set -euo pipefail
cd "$(dirname "$0")/.."

PROTON="/mnt/gaming/Steam/steamapps/common/Proton Hotfix/files/bin/wine"
MONO_DATA="/mnt/gaming/Steam/steamapps/common/Proton Hotfix/files/share/wine"
NEMESIS="/mnt/gaming/modlists/LoreRim/mods/Project New Reign - Nemesis Unlimited Behavior Engine/Nemesis_Engine/Papyrus Compiler"
PAPYRUS="$NEMESIS/PapyrusCompiler.exe"
FLAGS="$NEMESIS/scripts/TESV_Papyrus_Flags.flg"
IMPORTS="$PWD/Source/Scripts"
IMPORTS+=";/mnt/gaming/modlists/LoreRim/mods/Skyrim Script Extender (SKSE64)/Scripts/Source"
IMPORTS+=";/mnt/gaming/modlists/LoreRim/mods/Custom Skills Framework/Source/Scripts"
IMPORTS+=";/mnt/gaming/modlists/LoreRim/mods/powerofthree's Papyrus Extender/Source/scripts"
IMPORTS+=";/mnt/gaming/modlists/LoreRim/mods/PapyrusUtil SE - Modders Scripting Utility Functions/Source/Scripts"
IMPORTS+=";$NEMESIS/scripts"

scripts=("$@")
if [[ "${1:-}" == "all" ]]; then
    scripts=(MRO_StartupQuest MRO_MCM MRO_AbsorbMGEF MRO_EventsMGEF)
fi
[[ ${#scripts[@]} -gt 0 ]] || { echo "usage: tools/compile.sh <ScriptName>... | all" >&2; exit 1; }

fail=0
for s in "${scripts[@]}"; do
    out=$(WINEDATADIR="$MONO_DATA" "$PROTON" "$PAPYRUS" "Source/Scripts/$s.psc" \
        -f="$FLAGS" -i="$IMPORTS" -o="MRO-nofomod/Scripts" 2>&1) || true
    if grep -q "1 succeeded, 0 failed" <<<"$out"; then
        cp "MRO-nofomod/Scripts/$s.pex" "MRO-flat/Scripts/"
        echo "OK   $s"
    else
        echo "FAIL $s"
        grep -E "\.psc\(" <<<"$out" | head -10
        fail=1
    fi
done
exit $fail
