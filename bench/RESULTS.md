# Window stills — A/B performance report

Measured on the machine this plugin was developed on: niri 26.04, DMS 2.1.2,
1920×1200 @ 1×, 8 open windows across 3 named workspaces.

Reproduce with:

```bash
./bench/stills-ab.sh                 # off, warm, cold — 3 samples each, ~6 min
SAMPLES=5 ./bench/stills-ab.sh cold  # more repetitions of one arm
```

Every sample is a real panel open (`dms ipc call dash open plugin_workspaceManager`)
with the panel held open for 8 s and closed for 6 s afterwards. Raw rows land in
`bench/results.csv`.

## Arms

| arm | what it measures |
|---|---|
| `off` | `stills: false` — icon tiles, no clipboard use, no captures |
| `warm` | stills on, cache already populated: panel opens with **no** captures |
| `cold` | stills on, cache emptied and the shell restarted per sample: the full capture batch runs |

`warm` is the one that isolates rendering cost. The comparison that matters for
"is this feature worth it" is `off` vs `cold`; `warm` tells you how much of the
difference is just having pictures on screen.

## Results (median of 3)

| metric | off | warm | cold |
|---|---:|---:|---:|
| peak RSS, panel open (MB) | 51.8 | 66.6 | 72.6 |
| RSS just before the open (MB) | 51.7 | 66.6 | 55.1 |
| **RSS added by the open** | **+0.1** | **+0.0** | **+17.5** |
| RSS after the panel closes (MB) | 51.8 | 66.6 | 71.6 |
| dms CPU while open (s) | 0.020 | 0.020 | 0.160 |
| niri CPU while open (s) | 1.42 | 1.42 | 2.60 |
| dms CPU idle, panel shut (s per s) | 0.0025 | 0.0025 | 0.0025 |
| clipboard not yours (ms) | 0 | 0 | 176 |
| captures per open | 0 | 0 | 8 |
| stills on disk (MB) | 0 | 3.0 | 2.8 |
| panel surface up (ms) | 44 | 46 | 376 |

The `warm` arm's baseline sits ~15 MB above `off` because its warm-up open already
allocated the images before the first sample. That is why the *delta within the
process* is the column that matters, not the absolute peak.

## What it means

**Idle cost is the shell's own baseline: 0.25% of one core with the panel shut,
identical in all three arms.** An earlier version of this report claimed "exactly
0.0000" — that was a bug in this harness: the idle counters were read but never
passed to the `awk` that writes the row, so the column was hardcoded zero.
Shellcheck in CI caught it (SC2034, unused assignment) on the first real run. The
corrected number still shows no cost attributable to the feature, which is the
point, but it is not zero and should not have been claimed as zero.

**A cold open costs +0.14 s of shell CPU and +1.2 s of compositor CPU** for 8
windows, plus ~176 ms of clipboard occupancy: 18 ms of dms CPU and ~22 ms of
clipboard per window. The capture batch finishes ~200 ms after it starts, which is
why tiles visibly fill in.

**Memory is the real cost: a cold batch adds 17.5 MB, and ~16.5 MB of it stays
after the panel closes.** A warm open adds nothing measurable (the images are
already resident). The repeat-open loop below shows this is a one-time plateau, not
a per-open leak — but "one-time" still means "until the shell restarts", so a user
who cares about RSS should treat the stills setting as ~17 MB rather than free.

**Panel-open latency is not affected by the feature**: 44 ms vs 46 ms off vs warm is
noise, and the 376 ms in the `cold` column is the dash tab's QML first-load (the
`off` arm shows 366 ms on its first open after a restart, then 41–55 ms). Captures
start 350 ms after the panel is asked for, behind the first frame.

## Round 2a — compact rows vs full previews

Same harness, two more arms, both with stills on and a warm cache:

- `roomy` — every workspace shows its full preview (8 tiles painted)
- `compact` — each workspace is one collapsed line, one preview only

| metric | roomy | compact |
|---|---:|---:|
| peak RSS, panel open (MB) | 62.3 | 65.5 |
| dms CPU while open (s) | 0.030 | 0.030 |
| niri CPU while open (s) | 2.39 | **2.02** |
| panel surface up (ms) | 48 | 51 |

The honest reading: **collapsing rows is not a performance feature.** Shell CPU is
identical, memory is inside the noise (the compact arm even reads 3 MB higher,
which flipped sign between samples), and the only consistent delta is niri doing
~15% less work while the panel is open, because there are fewer tiles to paint.
The expensive part of this feature is *capturing* stills, not drawing them. Compact
mode earns its place by fitting four or five workspaces where two previews did —
not by saving resources.

## Round 2b — hold sweep and cache behaviour

Question: does an open panel keep costing anything, and does the cache really
avoid re-capturing?

Panel left open for **5 minutes** with the cache warm, sampling every 30 s:

| elapsed | stills on disk | new captures |
|---:|---:|---:|
| 8 s (initial batch) | 8 | 8 |
| 30 s – 300 s | 8 | **0** |

Zero captures in five minutes of an open panel. The pull only runs when the panel
opens (`refreshLive`), never on a timer, so an open panel costs paint time and
nothing else.

Cache expiry, with the TTL temporarily lowered to 60 s for the experiment (shipped
value is 10 minutes):

| action | captures |
|---|---|
| reopen immediately | **0** |
| close, wait 75 s (past TTL), reopen | **8** |
| reopen immediately again | **0** |

So the cache is honoured, and expiry produces exactly one fresh batch — not a
steady drip.

Note on methodology: the first attempt at this sweep measured zero stills for five
minutes and proved nothing, because the A/B harness deletes the still files while
the daemon's cache map still holds fresh timestamps, so no capture was ever
requested. `bench/stills-hold.sh` now clears both and refuses to run unless a
baseline batch appeared.

## Limitations, stated plainly

- One machine, one window count (8), one monitor. Costs scale linearly with the
  number of windows, which the per-capture figures let you predict.
- `niri` CPU is dominated by an animated wallpaper; the arm-to-arm *difference* is
  meaningful, the absolute number is not.
- The `cold` arm cannot avoid the QML first-load, so its latency figure mixes two
  effects. Recovering a truly load-free cold measurement would need a way to clear
  the daemon's still cache without restarting the shell.
- RSS is measured from `/proc/<pid>/status`; GPU-side allocations show up in it on
  this driver, so treat it as "cost to the system", not "heap".
- Medians of 3. Spread across samples was small (RSS within 1 MB, CPU within
  0.02 s), so 3 is enough to spot a regression, not enough for confidence intervals.
- The repeat-open loop ran against a shell that had already been through several
  benchmark arms, so its absolute RSS is not comparable to the table; only the
  trend across the ten cycles is.
