#!/usr/bin/env bash
# 16:9 logo for marth Resurgence Overhaul (1920x1080) — sibling of MEO's
# make_logo_16x9.sh and this repo's make_banner.sh: the banner's motif (a
# progression curve breaking past the cap line, diamond spark at the tip)
# recomposed as a centered hero above stacked typography. House style: dark
# ground, warm ember glow, gold curve, P052 type. Use for splash / Nexus
# header / video thumbnail.
set -euo pipefail
cd "$(dirname "$0")"
W=1920; H=1080
P052=/usr/share/fonts/opentype/urw-base35/P052-Roman.otf
P052I=/usr/share/fonts/opentype/urw-base35/P052-Italic.otf

# The resurgence curve, centered on cx=960 in the upper third: flat approach
# from the left, breaking through the cap line, surging to a spark at the tip.
CURVE="M 620,555 C 790,548 950,505 1065,425 C 1170,352 1240,295 1288,238"
CAPY=430

# 1) Base: near-black vertical gradient + soft ember radial glow (centered).
magick -size ${W}x${H} gradient:'#16181d-#08090b' \
  \( -size ${W}x${H} radial-gradient:'#2a2417-#000000' -evaluate multiply 0.9 \) \
  -compose screen -composite base.png

# 2) The emblem: faint cap line the curve breaks through, blurred gold glow
#    underlayer, then the crisp two-tone gold curve + diamond spark at the tip.
magick base.png \
  -stroke '#3b3f47' -strokewidth 2 -fill none \
  -draw "line 600,${CAPY} 1320,${CAPY}" \
  \( -clone 0 -fill none -stroke '#c9a45c' -strokewidth 14 \
     -draw "path '$CURVE'" -blur 0x12 \) -compose screen -composite \
  -fill none -stroke '#e8c87e' -strokewidth 4 -draw "path '$CURVE'" \
  -stroke '#c9a45c' -strokewidth 1.6 -draw "path '$CURVE'" \
  -stroke none -fill '#f4dfa8' \
  -draw "translate 1288,238 rotate 45 rectangle -7,-7 7,7" \
  emblem.png

# 3) Typography — centered stack below the emblem (MEO-matched layout).
magick emblem.png -gravity north \
  -font "$P052" \
  -fill '#9a8a5e' -pointsize 44 -kerning 22 -annotate +0+630 "m a r t h" \
  -fill '#eae1cb' -pointsize 128 -kerning 8 -annotate +0+688 "RESURGENCE" \
  -fill '#c9a45c' -pointsize 40 -kerning 34 -annotate +6+840 "O V E R H A U L" \
  -font "$P052I" -fill '#8d939e' -pointsize 30 -kerning 1 \
  -annotate +0+928 "late-game progression past the cap  —  the ceiling is where it begins" \
  logo-16x9.png
rm -f base.png emblem.png
echo "wrote logo-16x9.png (${W}x${H})"
