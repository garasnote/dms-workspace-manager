#!/usr/bin/env bash
# Duration sweep: hold the panel open and see whether the stills feature keeps
# costing anything after the first batch. The cache TTL is 10 minutes, so an
# 11-minute hold crosses it exactly once.
#
#   ./bench/stills-hold.sh 660        # seconds to hold (default 660)
#
# Prints one row every 30 s: elapsed, dms CPU in that slice, niri CPU in that
# slice, RSS of the shell, stills on disk, captures in that slice.
set -uo pipefail

HOLD="${1:-660}"
SLICE=30
STILLS_DIR="/tmp/wsm-stills"
TICKS=$(getconf CLK_TCK)
OUT="${OUT:-/tmp/hold.csv}"

cpu() { awk '{print $14+$15+$16+$17}' "/proc/$1/stat" 2>/dev/null || echo 0; }
rss() { awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0; }
n_stills() { find "$STILLS_DIR" -name '*.png' 2>/dev/null | wc -l; }

dms_pid=$(pgrep -x dms | head -1)
niri_pid=$(pgrep -x niri | head -1)
[[ -z "$dms_pid" || -z "$niri_pid" ]] && { echo "dms/niri not running" >&2; exit 1; }

# make sure stills are on and the cache is warm before the clock starts
python3 - "$HOME/.config/dms/plugin_settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("workspaceManager", {})["stills"] = True
json.dump(d, open(p, "w"), indent=2)
PY
# force a capture batch up front: the daemon's cache map can outlive the files on
# disk (the A/B harness deletes them), and then nothing would be captured at all
rm -rf "$STILLS_DIR"
dms ipc call dash close >/dev/null 2>&1
sleep 1
dms ipc call dash open plugin_workspaceManager >/dev/null 2>&1
sleep 10
dms ipc call dash close >/dev/null 2>&1
sleep 2
[ "$(n_stills)" -gt 0 ] || { echo "no stills captured; aborting" >&2; exit 1; }

echo "elapsed_s,dms_cpu_s,niri_cpu_s,rss_kb,stills,captures" > "$OUT"
dms ipc call dash open plugin_workspaceManager >/dev/null 2>&1
sleep 2

d0=$(cpu "$dms_pid"); n0=$(cpu "$niri_pid"); f0=$(n_stills); start=$(date +%s)
now=$start
while (( now - start < HOLD )); do
  sleep "$SLICE"
  d1=$(cpu "$dms_pid"); n1=$(cpu "$niri_pid"); f1=$(n_stills); now=$(date +%s)
  awk -v e=$((now-start)) -v t="$TICKS" -v d0="$d0" -v d1="$d1" -v n0="$n0" -v n1="$n1" \
      -v r="$(rss "$dms_pid")" -v f="$f1" -v c=$((f1-f0)) \
      'BEGIN{printf "%d,%.3f,%.3f,%d,%d,%d\n", e, (d1-d0)/t, (n1-n0)/t, r, f, c}'
  # rewrite the csv so a partial run is still usable
  awk -v e=$((now-start)) -v t="$TICKS" -v d0="$d0" -v d1="$d1" -v n0="$n0" -v n1="$n1" \
      -v r="$(rss "$dms_pid")" -v f="$f1" -v c=$((f1-f0)) \
      'BEGIN{printf "%d,%.3f,%.3f,%d,%d,%d\n", e, (d1-d0)/t, (n1-n0)/t, r, f, c}' >> "$OUT"
  d0=$d1; n0=$n1; f0=$f1
done
dms ipc call dash close >/dev/null 2>&1
echo "csv: $OUT" >&2
