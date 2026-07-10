#!/usr/bin/env bash
# Nexus banner for marth Resurgence Overhaul (1300x372).
# Motif: a progression curve breaking past the "cap" line and surging upward.
set -euo pipefail
W=1300; H=372
P052=/usr/share/fonts/opentype/urw-base35/P052-Roman.otf
P052I=/usr/share/fonts/opentype/urw-base35/P052-Italic.otf

# 1) Base: near-black vertical gradient + soft radial glow behind the title
magick -size ${W}x${H} gradient:'#16181d-#08090b' \
  \( -size ${W}x${H} radial-gradient:'#2a2417-#000000' -evaluate multiply 0.9 \) \
  -compose screen -composite base.png

# 2) The cap line (faint) + the resurgence curve (glow underlayer, then crisp)
magick base.png \
  -stroke '#3b3f47' -strokewidth 1.5 -fill none \
  -draw "line 70,262 1230,262" \
  -stroke '#c9a45c' -strokewidth 9 -fill none \
  -draw "path 'M 70,332 C 480,328 830,318 1005,270 C 1105,240 1180,150 1228,58'" \
  -channel RGBA -blur 0x6 \
  -stroke '#e8c87e' -strokewidth 2.5 -fill none \
  -draw "path 'M 70,332 C 480,328 830,318 1005,270 C 1105,240 1180,150 1228,58'" \
  -stroke none -fill '#f4dfa8' \
  -draw "translate 1228,58 rotate 45 rectangle -5,-5 5,5" \
  curve.png

# 3) Typography
magick curve.png \
  -font "$P052" -fill '#9a8a5e' -pointsize 30 -kerning 14 \
  -gravity north -annotate +2+64 "m a r t h" \
  -fill '#eae1cb' -pointsize 92 -kerning 6 \
  -annotate +0+96 "RESURGENCE" \
  -fill '#c9a45c' -pointsize 26 -kerning 22 \
  -annotate +6+206 "O V E R H A U L" \
  -font "$P052I" -fill '#8d939e' -pointsize 22 -kerning 1 \
  -annotate +0+276 "late-game progression past the cap  —  the ceiling is where it begins" \
  nexus-banner.png
rm -f base.png curve.png
