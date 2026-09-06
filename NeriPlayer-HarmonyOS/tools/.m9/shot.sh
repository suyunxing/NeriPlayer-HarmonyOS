#!/bin/sh
# dev-only: capture screen + layout for the M9.3 walkthrough
# usage: shot.sh <tag>
tag="$1"
hdc shell snapshot_display -f /data/local/tmp/s.jpeg >/dev/null 2>&1
hdc file recv /data/local/tmp/s.jpeg tools/.m9/m93/m93_${tag}.jpeg >/dev/null 2>&1
hdc shell uitest dumpLayout -p /data/local/tmp/s.json >/dev/null 2>&1
hdc file recv /data/local/tmp/s.json tools/.m9/m93/m93_${tag}.json >/dev/null 2>&1
python tools/.m9/dumptxt.py tools/.m9/m93/m93_${tag}.json 2>&1 | head -60
