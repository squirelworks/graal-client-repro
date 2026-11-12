#!/bin/sh
# Lab check against an owner-supplied Linux 3.04 install. Nothing here is
# shipped in the repository: point TORQUE304_RELEASE at the install's
# release/ folder and TORQUE304_SHOT at the stage 0 main-menu screenshot
# (1024x768, menu at the top left). Skips when TORQUE304_RELEASE is unset.
# The menu render check also needs the tq-shot tool (second argument).
# TORQUE304_SCREEN_PNG (graalscreen.jpg converted to PNG) is optional now
# that the renderer reads the install's JPEG itself; a PNG given here is
# used first.
#
# Expected values are this project's own measurements of those files
# (README.md, "Lab results").
set -u
INSPECT=${1:-build/gui-inspect}
SHOT=${2:-build/tq-shot}
if [ -z "${TORQUE304_RELEASE:-}" ]; then
  echo "lab_check: TORQUE304_RELEASE not set, skipped"
  exit 0
fi
UI="$TORQUE304_RELEASE/common/ui"
fail=0

check_font() {  # file, expected first line
  got=$("$INSPECT" font "$UI/cache/$1" | head -n 1)
  if [ "$got" != "$2" ]; then echo "FAIL font $1: $got"; fail=1; fi
}
check_font "Arial_12.gft"          "version 1 height 12 baseline 9 glyphs 224 mapped 224 sheets 1"
check_font "Arial_13.gft"          "version 1 height 13 baseline 10 glyphs 224 mapped 224 sheets 1"
check_font "Arial_14.gft"          "version 1 height 14 baseline 11 glyphs 224 mapped 224 sheets 1"
check_font "Arial_16.gft"          "version 1 height 16 baseline 13 glyphs 224 mapped 224 sheets 1"
check_font "Arial_20.gft"          "version 1 height 19 baseline 15 glyphs 224 mapped 224 sheets 1"
check_font "Arial_24.gft"          "version 1 height 24 baseline 19 glyphs 224 mapped 224 sheets 1"
check_font "Arial_36.gft"          "version 1 height 36 baseline 29 glyphs 224 mapped 224 sheets 2"
check_font "Arial Bold_14.gft"     "version 1 height 10 baseline 8 glyphs 224 mapped 224 sheets 1"
check_font "Arial Bold_16.gft"     "version 1 height 16 baseline 13 glyphs 224 mapped 224 sheets 1"
check_font "Isabelle_14.gft"       "version 1 height 10 baseline 8 glyphs 224 mapped 224 sheets 1"
check_font "Isabelle_20.gft"       "version 1 height 20 baseline 16 glyphs 224 mapped 224 sheets 1"
check_font "Isabelle Bold_14.gft"  "version 1 height 10 baseline 8 glyphs 224 mapped 224 sheets 1"
check_font "Lucida Console_12.gft" "version 1 height 12 baseline 9 glyphs 224 mapped 224 sheets 1"
check_font "Lucida Console_14.gft" "version 1 height 14 baseline 11 glyphs 224 mapped 224 sheets 1"

check_array() {  # theme/file, expected cells, expected bands
  got=$("$INSPECT" array "$UI/themes/$1" | head -n 1 | sed 's/.* cells \([0-9]*\) bands \([0-9]*\)$/\1 \2/')
  if [ "$got" != "$2 $3" ]; then echo "FAIL array $1: $got, expected $2 $3"; fail=1; fi
}
while read -r name cells bands; do
  check_array "$name" "$cells" "$bands"
done <<'LIST'
default/default3darrow.png 1 1
default/defaultBorder.png 8 2
default/defaultButton.png 36 12
default/defaultCheck.png 4 4
default/defaultCursor.png 1 1
default/defaultGuiBorder.png 9 3
default/defaultMenu.png 18 6
default/defaultRadio.png 4 4
default/defaultScroll.png 52 12
default/defaultSlider.png 5 2
default/defaultTextEdit.png 8 3
default/defaultWindow.png 24 8
mac/macCheck.png 4 4
mac/macMenu.png 18 6
mac/macRadio.png 4 4
mac/macScroll.png 39 13
mac/macWindow.png 23 7
windows/windowsBorder.png 8 2
windows/windowsButton.png 36 12
windows/windowsCheck.png 4 4
windows/windowsCursor.png 1 1
windows/windowsGuiBorder.png 9 3
windows/windowsMenu.png 18 6
windows/windowsRadio.png 4 4
windows/windowsScroll.png 51 11
windows/windowsSlider.png 5 2
windows/windowsTextEdit.png 8 3
windows/windowsWindow.png 23 7
LIST

if [ -n "${TORQUE304_SHOT:-}" ]; then
  # Button labels sit on a flat fill, so the composited text must match the
  # screenshot pixel for pixel. The other labels sit on textured art and
  # are held to the glyph mask only.
  check_text() {  # font, text, x, y, measure (mask|exact), minimum
    line=$("$INSPECT" match "$UI/cache/$1" "$2" "$TORQUE304_SHOT" "$3" "$4")
    got=$(printf '%s\n' "$line" | sed "s/.*$5 \([0-9.]*\).*/\1/")
    if ! awk -v g="$got" -v m="$6" 'BEGIN { exit !(g + 0 >= m + 0) }'; then
      echo "FAIL text '$2' at $3,$4: $line ($5 below $6)"; fail=1
    else
      echo "text '$2' at $3,$4: $line"
    fi
  }
  check_text Arial_14.gft "Tutorial"          575 310 exact 1
  check_text Arial_14.gft "Options"           574 341 exact 1
  check_text Arial_14.gft "Get an account"    553 372 exact 1
  check_text Arial_14.gft "Start"             581 433 exact 1
  check_text Arial_14.gft "Account:"          201 418 mask 0.98
  check_text Arial_14.gft "Password:"         201 451 mask 0.98
  check_text Arial_20.gft "Welcome to Graal!" 266 299 mask 0.92

  # The main menu drawn by tq-shot from the install's own scripts, profiles
  # and theme, box by box against the screenshot. Buttons and the text
  # edits that do not have the keyboard focus are opaque, so they do not
  # depend on the JPEG art behind them. AccountEdit (the focused edit, with
  # the text cursor) and LanguageBox (pop-up menu, no measured figure yet)
  # are left out.
  tmp=$(mktemp -d)
  mkdir -p "$tmp/prefs/graaldata/client/ui"
  if [ -n "${TORQUE304_SCREEN_PNG:-}" ]; then
    cp "$TORQUE304_SCREEN_PNG" "$tmp/prefs/graaldata/client/ui/graalscreen.png"
  fi
  if ! "$SHOT" --root "$TORQUE304_RELEASE" --prefs "$tmp/prefs" --out "$tmp/menu.png" 2>"$tmp/notes"; then
    echo "FAIL tq-shot: $(cat "$tmp/notes")"; fail=1
  else
    check_box() {  # name, x, y, w, h, minimum
      got=$("$INSPECT" compare "$tmp/menu.png" "$TORQUE304_SHOT" "$2" "$3" "$4" "$5" | sed 's/exact //')
      if ! awk -v g="$got" -v m="$6" 'BEGIN { exit !(g + 0 >= m + 0) }'; then
        echo "FAIL menu $1: exact $got below $6"; fail=1
      else
        echo "menu $1: exact $got"
      fi
    }
    check_box "background"         0   0 800  92 1
    check_box "StartTutorialButton" 538 304 110 25 1
    check_box "StartOptionsButton"  538 335 110 25 1
    check_box "StartGetAccountButton" 521 366 138 25 1
    check_box "StartConnectButton"  538 427 110 25 1
    check_box "NickEdit"            320 330 150 22 1
    check_box "PassEdit"            320 446 150 22 1
    if [ -n "${TORQUE304_SCREEN_PNG:-}" ]; then
      # Everything else differs only in LanguageBox and the text cursor.
      check_box "whole screen"        0   0 800 600 0.993
    fi
  fi
  rm -rf "$tmp"
else
  echo "lab_check: TORQUE304_SHOT not set, screenshot checks skipped"
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "lab_check: passed"
