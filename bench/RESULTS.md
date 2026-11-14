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
| peak RSS, panel open (MB) | 57.1 | 62.7 | 67.3 |
| RSS, panel closed (MB) | 57.1 | 62.6 | 67.3 |
| dms CPU while open (s) | 0.030 | 0.030 | 0.200 |
| niri CPU while open (s) | 2.40 | 2.42 | 3.25 |
| dms CPU idle, panel shut (s per s) | 0.0000 | 0.0000 | 0.0000 |
| clipboard not yours (ms) | 0 | 0 | 240 |
| captures per open | 0 | 0 | 8 |
| stills on disk (MB) | 0 | 2.0 | 2.4 |
| panel surface up (ms) | 56 | 51 | 389 |

## What it means

**Idle cost is exactly zero.** The whole feature is pull-based: no timer, no
stream, no watcher. With the panel shut, dms burns 0.0000 s of CPU per second in
every arm, and niri has no idea the feature exists.

**A cold open costs about 0.17 s of shell CPU and 0.85 s of compositor CPU**, for
8 windows: 21 ms of dms CPU and ~30 ms of clipboard occupancy per window, plus
0.85 s of extra niri work spread across the 8 s the panel is open (niri is
already using ~30% of a core there, because the wallpaper animates — that is the
baseline, not the plugin). In wall-clock terms the capture batch finishes ~200 ms
after it starts, which is why tiles visibly fill in.

**Memory is the most expensive part: +10.2 MB peak with pictures, +5.6 MB of it
just from having images on screen** (warm), the remaining ~4.6 MB from holding the
extra decoded batch. That figure is measured on the first open after a restart, so
it includes one-off allocations. A repeat-open loop (below) shows it is a plateau,
not a leak.
Capping the decode at 320 px (from 420) cut 6.3 MB off the warm arm and 0.8 MB off
the disk footprint; that change came out of this benchmark.

**The clipboard is out of your hands for 240 ms per cold open**, 30 ms at a time,
one window per capture. Never longer, and never at all in the `warm` and `off` arms.

**Panel-open latency is not affected by the feature.** 51 ms warm vs 56 ms off is
noise. The 389 ms in the `cold` column is the dash tab's own QML first-load, and
the `off` arm proves it: that arm only restarts once, and its numbers are 430 ms
for the first open and 43–56 ms afterwards. The cold arm restarts per sample, so
every one of its opens pays that load. Captures themselves start 350 ms after the
panel is asked for, i.e. behind the first frame, precisely so they cannot compete
with it.

## Repeat-open check (is the retained RSS a leak?)

Ten consecutive open/close cycles with a cleared cache, sampling RSS of the shell
while the panel was shut:

| | RSS, panel closed |
|---|---:|
| before | 56.5 MB |
| after open 1 | 56.5 MB |
| after open 2 | 54.5 MB |
| after open 3–10 | 54.5–54.7 MB (flat) |

No creep: the second open actually drops 2 MB below where it started, as Qt
releases caches, and ten cycles stay inside a 200 kB band while re-capturing eight
windows every time. So the feature's steady-state footprint is a plateau, and the
"+10 MB" from the A/B table is the cost *while the panel is open*, not memory lost
per open.

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
