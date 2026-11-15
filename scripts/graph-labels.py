#!/usr/bin/env python3
"""Give graphify's communities human names.

graphify only invents labels when it can reach an LLM backend, and without one it
falls back to naming each community after its most-connected node. That produces
"steps" twice (two YAML workflow files), "ref_showemptyworkspaces", and one entry
per QML file. This script applies a curated table instead, and rewrites the three
artifacts that carry labels so they agree:

  graphify-out/graph.json        node.community_name
  graphify-out/GRAPH_REPORT.md   the "Community Hubs" list
  graphify-out/graph.html        the LEGEND blob

Re-run it after `graphify update .` or `graphify cluster-only .`, both of which
re-derive the fallback labels and would otherwise undo this.

    python3 scripts/graph-labels.py            # apply
    python3 scripts/graph-labels.py --check    # exit 1 when a community is unlabelled
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Community id -> human name. Ids are stable as long as the graph is only
# re-extracted (`graphify update`), which is what this repo does; re-clustering
# can renumber them, hence --check below.
LABELS: dict[int, str] = {
    0: "Dash UI: workspace cards and actions",
    1: "Live state publication",
    2: "Daemon core: workspace bookkeeping",
    3: "Plugin manifest",
    4: "niri IPC transport and workspace verbs",
    5: "A/B stills benchmark harness",
    6: "Registry entry",
    7: "Launch diff and window reconciliation",
    8: "Template persistence and status",
    9: "Window stills: capture cost and record",
    10: "Release workflow",
    11: "CI workflow",
    12: "Duration sweep script",
    13: "Docs and publishing guide",
    14: "App icon chip",
    15: "Workspace creation and template launch",
    16: "Launcher entry",
    17: "Mini-map layout math",
    18: "Settings pane",
    19: "Scrolling title label",
    20: "Local and CI checks script",
    21: "Emoji palette",
}

OUT = Path(__file__).resolve().parent.parent / "graphify-out"


def main() -> int:
    check_only = "--check" in sys.argv

    graph_path = OUT / "graph.json"
    graph = json.loads(graph_path.read_text())
    nodes = graph["nodes"]

    present = {n["community"] for n in nodes if n.get("community") is not None}
    unlabelled = sorted(present - set(LABELS))
    if unlabelled:
        print(f"unlabelled communities present: {unlabelled}", file=sys.stderr)
        print("re-clustering has renumbered them; update LABELS in this script", file=sys.stderr)
        if check_only:
            return 1

    if check_only:
        drift = [cid for cid in present if cid in LABELS
                 and any(n.get("community") == cid and n.get("community_name") != LABELS[cid] for n in nodes)]
        if drift:
            print(f"communities with stale labels: {drift}", file=sys.stderr)
            return 1
        print(f"{len(present)} communities labelled")
        return 0

    for n in nodes:
        cid = n.get("community")
        if cid in LABELS:
            n["community_name"] = LABELS[cid]
    graph_path.write_text(json.dumps(graph, indent=1))

    # ---- report: replace the "Community Hubs" bullet list, keep everything else
    report_path = OUT / "GRAPH_REPORT.md"
    if report_path.exists():
        text = report_path.read_text()
        order = sorted(present, key=lambda c: -sum(1 for n in nodes if n.get("community") == c))
        hubs = "\n".join(f"- {LABELS[cid]}" for cid in order if cid in LABELS)
        text = re.sub(
            r"(## Community Hubs \(Navigation\)\n)(?:- .*\n)+",
            lambda m: m.group(1) + hubs + "\n",
            text,
        )
        report_path.write_text(text)

    # ---- html: rewrite the LEGEND blob
    html_path = OUT / "graph.html"
    if html_path.exists():
        html = html_path.read_text()

        def fix(match: re.Match) -> str:
            legend = json.loads(match.group(1))
            for item in legend:
                cid = item.get("cid")
                if cid in LABELS:
                    item["label"] = LABELS[cid]
            return "const LEGEND = " + json.dumps(legend) + ";"

        html, n = re.subn(r"const LEGEND = (\[.*?\]);", fix, html, count=1)
        html_path.write_text(html)
        print(f"graph.html legend rewritten: {n}")

    print(f"applied {len(set(LABELS) & present)} labels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
