#!/usr/bin/env python3
"""S2 — per-machine stage timeline from the I1 transition log via Loki.

Usage: loki-stage-timeline.py <run-name> <from-iso> <to-iso> [--loki-url URL]

Pulls every `state_transition_committed` line for the machine controller in
the window and writes runs/<run-name>/timeline-loki.csv with the schema
  machine_id,ts,from_state,from_substate,to_state,to_substate,dwell_ms
Cross-check against timeline-sql.csv (S1): same transition count per machine,
dwell agreement within ~1s.
"""

import argparse
import csv
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse
import urllib.request

import os
RUNS_DIR = pathlib.Path(os.environ.get("BENCH_RUNS_DIR",
                                       pathlib.Path.home() / "stage-timing-runs"))
QUERY = '{namespace="nico-system"} |= "state_transition_committed" | logfmt'
# The otel-agent's stream labels vary by config; try these selectors in order.
FALLBACK_QUERIES = [
    QUERY,
    '{k8s_namespace_name="nico-system"} |= "state_transition_committed" | logfmt',
    '{job=~".+"} |= "state_transition_committed" | logfmt',
]
FIELD_RE = re.compile(r'(\w+)=(?:"((?:[^"\\]|\\.)*)"|(\S+))')


def loki_url_from_kubectl() -> str:
    if os.environ.get("LOKI_URL"):
        return os.environ["LOKI_URL"]
    # helm-prereqs/observability stack first, then k3s-dev fallbacks
    for ns, name in [("observability", "loki"), ("loki", "loki"),
                     ("monitoring", "loki"), ("observability", "loki-gateway")]:
        r = subprocess.run(
            ["timeout", "30", "kubectl", "get", "svc", "-n", ns, name,
             "-o", "jsonpath={.spec.clusterIP}"],
            capture_output=True, text=True)
        ip = r.stdout.strip()
        if r.returncode == 0 and ip and ip != "None":
            return f"http://{ip}:3100"
    sys.exit("ERROR: could not resolve a Loki service; set LOKI_URL")


def to_ns(iso: str) -> int:
    d = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return int(d.timestamp() * 1e9)


def fetch(base: str, query: str, start_ns: int, end_ns: int):
    """Page through query_range (forward) until the window is exhausted."""
    out, cursor = [], start_ns
    while True:
        params = urllib.parse.urlencode({
            "query": query, "start": cursor, "end": end_ns,
            "limit": 5000, "direction": "forward",
        })
        req = urllib.request.Request(
            f"{base}/loki/api/v1/query_range?{params}",
            headers={"X-Scope-OrgID": "forge"})  # accepted (and collapsed) by the site stack
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.load(resp)
        entries = [
            (int(ts), line)
            for stream in data.get("data", {}).get("result", [])
            for ts, line in stream.get("values", [])
        ]
        entries.sort()
        out.extend(entries)
        if len(entries) < 5000:
            return out
        cursor = entries[-1][0] + 1


def parse_line(line: str) -> dict:
    # findall yields '' (not None) for the non-participating alternative
    return {k: (q or b) for k, q, b in FIELD_RE.findall(line)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_name")
    ap.add_argument("from_iso")
    ap.add_argument("to_iso")
    ap.add_argument("--loki-url", default=None)
    args = ap.parse_args()

    base = args.loki_url or loki_url_from_kubectl()
    start_ns, end_ns = to_ns(args.from_iso), to_ns(args.to_iso)

    entries = []
    for q in FALLBACK_QUERIES:
        try:
            entries = fetch(base, q, start_ns, end_ns)
        except urllib.error.HTTPError as e:
            print(f"selector failed ({e}): {q}", file=sys.stderr)
            continue
        if entries:
            break

    rows = []
    for ts, line in entries:
        f = parse_line(line)
        # the transition log is generic across ALL state controllers
        # (machines, network segments, ...); keep machine transitions only
        if f.get("controller") != "machine_state_controller":
            continue
        if f.get("object_id") and f.get("to_state"):
            rows.append({
                "machine_id": f["object_id"],
                "ts": dt.datetime.fromtimestamp(
                    ts / 1e9, dt.timezone.utc).isoformat(timespec="milliseconds"),
                "from_state": f.get("from_state", ""),
                "from_substate": f.get("from_substate", ""),
                "to_state": f.get("to_state", ""),
                "to_substate": f.get("to_substate", ""),
                "dwell_ms": f.get("dwell_ms", ""),
            })

    out = RUNS_DIR / args.run_name / "timeline-loki.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=[
            "machine_id", "ts", "from_state", "from_substate",
            "to_state", "to_substate", "dwell_ms"])
        w.writeheader()
        w.writerows(rows)

    machines = len({r["machine_id"] for r in rows})
    print(f"S2 OK: {len(rows)} transition events across {machines} objects -> {out}")
    if not rows:
        print("WARN: zero events — instrumented image not deployed, window wrong, "
              "or Loki stream labels differ (check FALLBACK_QUERIES)", file=sys.stderr)


if __name__ == "__main__":
    main()
