#!/bin/sh
# M9.3 walkthrough driver (dev-only, not shipped).
# Usage: walk.sh <tag> <tap_x> <tap_y> [settle_seconds]
# Scrolls the settings tab to its bottom, taps one row, dumps the layout,
# scans it, then pops back so the next call starts from a known state.
set -e
export MSYS_NO_PATHCONV=1
TAG="$1"; X="$2"; Y="$3"; SETTLE="${4:-3}"

hdc shell uinput -T -c 1155 2600 >/dev/null 2>&1
sleep 2
i=0
while [ $i -lt 4 ]; do
  hdc shell uinput -T -m 660 2100 660 800 250 >/dev/null 2>&1
  sleep 1
  i=$((i + 1))
done
sleep 1
hdc shell uinput -T -c "$X" "$Y" >/dev/null 2>&1
sleep "$SETTLE"
hdc shell "uitest dumpLayout -p /data/local/tmp/w_$TAG.json" >/dev/null 2>&1
hdc file recv "/data/local/tmp/w_$TAG.json" "tools/.m9/w_$TAG.json" >/dev/null 2>&1
python tools/.m9/overflow.py "tools/.m9/w_$TAG.json"
hdc shell "uitest uiInput keyEvent Back" >/dev/null 2>&1
sleep 2
