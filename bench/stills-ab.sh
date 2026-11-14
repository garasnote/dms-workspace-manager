#!/usr/bin/env bash
# A/B benchmark for the window-stills feature (WorkspaceDash / WorkspacePreview).
#
#   ./bench/stills-ab.sh                  # cold, warm, off — 3 samples each
#   SAMPLES=5 ./bench/stills-ab.sh cold   # more repetitions of one arm
#   OPEN_SECS=10 IDLE_SECS=8 ./bench/stills-ab.sh
#
# Arms
#   cold   stills on, cache emptied and dms restarted for every sample, so the
#          whole capture batch happens while the panel is open
#   warm   stills on, cache already populated: the panel opens with no captures,
#          which isolates render/decode cost from capture cost
#   off    stills disabled in plugin_settings.json: icon tiles, no clipboard use
#
# Everything is measured from outside the shell:
#   * RSS and CPU (incl. reaped children) from /proc/<pid>/stat and status
#   * clipboard occupancy by comparing wl-paste type lists against what you had
#     before the panel opened
#   * time to panel by polling niri's layer list for the "dms:dash" surface
# That last one replaces screenshot probing on purpose: a grim loop drives niri's
# compositor hard enough to swamp the thing being measured.
#
# Output: bench/results.csv, one row per sample, plus a median table on stdout.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$HOME/.config/dms/plugin_settings.json"
STILLS_DIR="/tmp/wsm-stills"
OUT_CSV="$PLUGIN_DIR/bench/results.csv"
ARMS=("$@")
[[ ${#ARMS[@]} -eq 0 ]] && ARMS=(cold warm off)

SAMPLES="${SAMPLES:-3}"
OPEN_SECS="${OPEN_SECS:-8}"
IDLE_SECS="${IDLE_SECS:-6}"
TICKS=$(getconf CLK_TCK)
TAB=$(mktemp)

log() { printf '%s\n' "$*" >&2; }

set_setting() { # true|false
  python3 - "$SETTINGS" "$1" <<'PY'
import json, sys
path, value = sys.argv[1], sys.argv[2] == "true"
data = json.load(open(path))
data.setdefault("workspaceManager", {})["stills"] = value
json.dump(data, open(path, "w"), indent=2)
PY
}

cpu_ticks() { awk '{print $14+$15+$16+$17}' "/proc/$1/stat" 2>/dev/null || echo 0; }
rss_kb() { awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0; }
clip_sig() { wl-paste --list-types 2>/dev/null | tr '\n' '|'; }
stills_count() { find "$STILLS_DIR" -name '*.png' 2>/dev/null | wc -l; }
stills_bytes() { du -sb "$STILLS_DIR" 2>/dev/null | cut -f1; }

wait_ready() {
  for _ in $(seq 1 60); do
    dms ipc call plugins status workspaceManager >/dev/null 2>&1 &&
      niri msg -j windows >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

panel_up_in_ms() { # ms until niri reports the dash layer surface
  local start now
  start=$(date +%s%3N)
  for _ in $(seq 1 400); do
    if niri msg -j layers 2>/dev/null | grep -q '"dms:dash"'; then
      now=$(date +%s%3N)
      echo $((now - start))
      return
    fi
    sleep 0.01
  done
  echo ""
}

sample_once() { # arm idx -> csv row on stdout
  local arm="$1" idx="$2"
  local dms_pid niri_pid
  dms_pid=$(pgrep -x dms | head -1)
  niri_pid=$(pgrep -x niri | head -1)
  [[ -z "$dms_pid" || -z "$niri_pid" ]] && { log "dms/niri not running"; return 1; }

  dms ipc call dash close >/dev/null 2>&1
  sleep 1

  local baseline_clip before_n
  baseline_clip=$(clip_sig)
  before_n=$(stills_count)

  local rss_closed cpu0 niri0
  rss_closed=$(rss_kb "$dms_pid")
  cpu0=$(cpu_ticks "$dms_pid")
  niri0=$(cpu_ticks "$niri_pid")

  panel_up_in_ms > "$TAB.up" &
  local probe_pid=$!
  dms ipc call dash open plugin_workspaceManager >/dev/null 2>&1

  local end rss_peak busy busy_polls
  end=$(( $(date +%s%3N) + OPEN_SECS * 1000 ))
  rss_peak=$rss_closed
  busy=0
  busy_polls=0
  while (( $(date +%s%3N) < end )); do
    local r now_sig
    r=$(rss_kb "$dms_pid")
    (( r > rss_peak )) && rss_peak=$r
    now_sig=$(clip_sig)
    [[ "$now_sig" != "$baseline_clip" ]] && busy=$((busy + 1))
    busy_polls=$((busy_polls + 1))
    sleep 0.05
  done

  local cpu1 niri1
  cpu1=$(cpu_ticks "$dms_pid")
  niri1=$(cpu_ticks "$niri_pid")

  wait "$probe_pid" 2>/dev/null
  local first_ms
  first_ms=$(cat "$TAB.up" 2>/dev/null)

  dms ipc call dash close >/dev/null 2>&1
  sleep 1
  local rss_after idle0 idle1
  rss_after=$(rss_kb "$dms_pid")

  idle0=$(cpu_ticks "$dms_pid")
  sleep "$IDLE_SECS"
  idle1=$(cpu_ticks "$dms_pid")

  local after_n bytes captured busy_ms
  after_n=$(stills_count)
  captured=$(( after_n - before_n ))
  bytes=$(stills_bytes)
  bytes=${bytes:-0}
  busy_ms=$(awk -v b="$busy" -v p="$busy_polls" -v d="$OPEN_SECS" 'BEGIN{ if (p>0) printf "%d", (b/p)*d*1000; else print 0 }')

  awk -v arm="$arm" -v idx="$idx" -v t="$TICKS" -v idle="$IDLE_SECS" \
      -v rss_closed="$rss_closed" -v rss_peak="$rss_peak" -v rss_after="$rss_after" \
      -v cpu0="$cpu0" -v cpu1="$cpu1" -v niri0="$niri0" -v niri1="$niri1" \
      -v busy_ms="$busy_ms" -v first_ms="${first_ms:-}" -v n="$after_n" -v b="$bytes" \
      -v cap="$captured" \
      'BEGIN{
         printf "%s,%d,%d,%d,%d,%.3f,%.3f,%.4f,%d,%s,%d,%d,%d\n",
           arm, idx, rss_closed, rss_peak, rss_after,
           (cpu1-cpu0)/t, (niri1-niri0)/t, (idle1-idle0)/t/idle,
           busy_ms, (first_ms=="" ? "NA" : first_ms), n, b, cap
       }'
}

restart_shell() {
  dms restart >/dev/null 2>&1
  sleep 6
  wait_ready || { log "shell did not come back"; return 1; }
  sleep 4
}

echo "arm,sample,rss_closed_kb,rss_open_peak_kb,rss_after_close_kb,dms_cpu_open_s,niri_cpu_open_s,dms_cpu_idle_s,clipboard_busy_ms,panel_up_ms,stills_count,stills_bytes,captures" > "$OUT_CSV"

restore() {
  set_setting true
  dms ipc call dash close >/dev/null 2>&1
  rm -f "$TAB" "$TAB.up"
  rm -rf "$STILLS_DIR"
}
trap restore EXIT

for arm in "${ARMS[@]}"; do
  log "== arm: $arm"
  case "$arm" in
    off)
      set_setting false
      rm -rf "$STILLS_DIR"
      restart_shell || continue
      for i in $(seq 1 "$SAMPLES"); do sample_once "$arm" "$i" | tee -a "$OUT_CSV"; done
      ;;
    warm)
      set_setting true
      rm -rf "$STILLS_DIR"
      restart_shell || continue
      dms ipc call dash open plugin_workspaceManager >/dev/null 2>&1
      sleep 8
      dms ipc call dash close >/dev/null 2>&1
      sleep 2
      for i in $(seq 1 "$SAMPLES"); do sample_once "$arm" "$i" | tee -a "$OUT_CSV"; done
      ;;
    cold)
      set_setting true
      for i in $(seq 1 "$SAMPLES"); do
        rm -rf "$STILLS_DIR"
        restart_shell || continue
        sample_once "$arm" "$i" | tee -a "$OUT_CSV"
      done
      ;;
    *)
      log "unknown arm: $arm"
      ;;
  esac
done

log ""
log "raw rows: $OUT_CSV"
python3 - "$OUT_CSV" <<'PY'
import csv, statistics, sys

rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    print("no samples")
    raise SystemExit

order = {"off": 0, "warm": 1, "cold": 2}
arms = sorted({r["arm"] for r in rows}, key=lambda a: order.get(a, 9))

def med(arm, key, scale=1.0):
    vals = [float(r[key]) for r in rows if r["arm"] == arm and r[key] not in ("", "NA")]
    return statistics.median(vals) / scale if vals else float("nan")

cols = [
    ("rss_open_peak_kb", "peak RSS, panel open (MB)", 1024, 1),
    ("rss_after_close_kb", "RSS, panel closed (MB)", 1024, 1),
    ("dms_cpu_open_s", "dms CPU while open (s)", 1, 3),
    ("niri_cpu_open_s", "niri CPU while open (s)", 1, 3),
    ("dms_cpu_idle_s", "dms CPU idle (s per s)", 1, 4),
    ("clipboard_busy_ms", "clipboard not yours (ms)", 1, 0),
    ("captures", "captures per open", 1, 1),
    ("stills_bytes", "stills on disk (MB)", 1048576, 1),
]
head = f"{'metric':30}" + "".join(f"{a:>11}" for a in arms)
print(head)
print("-" * len(head))
for key, label, div, digits in cols:
    print(f"{label:30}" + "".join(f"{med(a, key, div):>11.{digits}f}" for a in arms))
print(f"{'panel surface up (ms)':30}" + "".join(f"{med(a, 'panel_up_ms'):>11.0f}" for a in arms))
first = {a: [float(r["panel_up_ms"]) for r in rows if r["arm"] == a and r["panel_up_ms"] not in ("", "NA")][:1] for a in arms}
print(f"{'  first open after restart':30}" + "".join(f"{(f[0] if f else 0):>11.0f}" for f in first.values()))
print("  (first open pays the dash tab's QML load in every arm)")

if "off" in arms:
    print()
    for arm in [a for a in arms if a != "off"]:
        dc = med(arm, "dms_cpu_open_s") - med("off", "dms_cpu_open_s")
        dp = med(arm, "rss_open_peak_kb") - med("off", "rss_open_peak_kb")
        caps = med(arm, "captures")
        per = (dc / caps) if caps else float("nan")
        per_s = f"{per:.3f}" if per == per and caps else "n/a"
        print(f"{arm} vs off: {dc:+.3f} s dms CPU per open, "
              f"{dp/1024:+.1f} MB peak RSS, {per_s} s CPU per capture")
PY
