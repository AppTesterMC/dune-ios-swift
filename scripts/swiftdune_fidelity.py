#!/usr/bin/env python3
"""How close SwiftDune (iOS) is to the original: the fidelity report.

The scenarios are the ScummVM Dune engine's (Cryogenic-local
tests/fidelity/scenarios.json, harness-format scripts: click / move / wait /
checkpoint), scored against the same cached captures of the original
DUNEPRG.EXE (Spice86 autoplay in ~/Dune-DOS-reference) with the same rule:
the share of pixels within tolerance of the original's, the original's
cursor masked, a checkpoint not reached counting 0. Its scoring code is
imported from there, read-only, so the two reports are comparable.

Each script is translated to SwiftDune's DUNE_SCRIPT (time 0 = the throne
room after the intro, as the original's prelude) and run in the iOS
simulator with scripts/sim_run.sh (headless, silent). Two CD scenarios
compare the CD release with the original DNCDPRG.EXE's flight capture.

usage: scripts/swiftdune_fidelity.py [--only NAME ...] [--out DIR] [--offset S]
"""
from __future__ import annotations

import argparse
import datetime
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CRYO = Path(os.environ.get("CRYO_ROOT", Path.home() / "Cryogenic-local"))
sys.path.insert(0, str(CRYO / "scripts"))
import dune_fidelity as ref  # noqa: E402  (score, load, cursor_box, sheet, bar, checkpoints)

FIDELITY = CRYO / "tests/fidelity"
REFERENCE = Path.home() / "Dune-DOS-reference"
CAPTURES = REFERENCE / "captures"
SHOTS = HERE / "build/shots"

# The CD scenarios: SwiftDune's CD build against the original CD program
# (DNCDPRG.EXE on Spice86, autoplay-cd.sh with the CD prelude that skips
# the intro), with scripts made for the CD's rows (its rooms list Mixer
# Panel after the verbs).
FIDELITY_SCRIPTS = Path.home() / "Cryogenic-local/tests/fidelity"
CD_SCENARIOS = [
    {"name": "cd-speedrun-day1", "title": "CD: the day 1 speedrun (the ScummVM port's cd-speedrun-day1.script, "
     "made for the CD's rows)", "cd": True,
     "script": FIDELITY_SCRIPTS / "cd-speedrun-day1.script", "original": "cd-speedrun-day1"},
    {"name": "cd-flight", "title": "CD, new game: the palace front, TAKE AN ORNITHOPTER, Carthag-Tuek on the "
     "cockpit map, take-off, flight, arrival", "cd": True, "prelude_in_script": True,
     "script": REFERENCE / "autoplay/scripts/cd/flight.script", "original": "cd-flight"},
]


def waitds_times(script: Path, capture: Path | None) -> dict[int, float]:
    """How long each waitds line waited in the original's run, by script line."""
    log = capture / "autoplay.log" if capture else None
    if not log or not log.exists():
        return {}
    pattern = re.compile(re.escape(script.name) + r":(\d+): 'waitds [^']*' met after (\d+) ms")
    return {int(m.group(1)): int(m.group(2)) / 1000 for m in pattern.finditer(log.read_text())}


def translate(script: Path, offset: float, skip_prelude: bool = False,
              capture: Path | None = None) -> tuple[str, float, list[str]]:
    """Harness script -> DUNE_SCRIPT steps, the run's length and the checkpoints.
    A waitds (the original waiting on its memory) takes as long as it did in
    the capture."""
    t, steps, names = offset, [], []
    waited = waitds_times(script, capture)
    lines = list(enumerate(script.read_text().splitlines(), start=1))
    if skip_prelude:
        # The CD script boots the intro and skips it (ESC twice): SwiftDune
        # starts in the throne room, at the script's first checkpoint.
        start = next(i for i, (_, l) in enumerate(lines) if l.split()[:1] == ["checkpoint"])
        lines = lines[start:]
    for number, line in lines:
        tok = re.sub(r"\s#.*", "", line).split()  # inline comments
        if not tok or tok[0].startswith("#"):
            continue
        if tok[0] == "wait":
            t += int(tok[1]) / 1000
        elif tok[0] == "waitds":
            t += waited.get(number, 0.0)
        elif tok[0] == "click" and len(tok) >= 4:
            steps.append(f"{t:.2f}:click:{tok[2]},{tok[3]}")
        elif tok[0] == "move" and len(tok) >= 3:
            steps.append(f"{t:.2f}:hover:{tok[1]},{tok[2]}")
        elif tok[0] == "key" and len(tok) >= 2:
            key = {"ESC": "esc", "ESCAPE": "esc", "RETURN": "ret", "ENTER": "ret"}.get(tok[1].upper(), tok[1].lower())
            steps.append(f"{t:.2f}:key:{key}")
        elif tok[0] == "checkpoint":
            steps.append(f"{t:.2f}:shot:{tok[1]}")
            if tok[1] not in names:
                names.append(tok[1])
        elif tok[0] == "quit":
            break
    # A screenshot is taken at the next frame, and an input at the same time
    # would land first: inputs go 0.1 s after the checkpoints.
    steps = [x if ":shot:" in x else f"{float(x.split(':', 1)[0]) + 0.1:.2f}:{x.split(':', 1)[1]}" for x in steps]
    return ";".join(steps), t + 4, names


def capture_times(capture: Path) -> dict[str, float]:
    """The checkpoints' times in the original's run (its autoplay.log)."""
    times = {}
    log = capture / "autoplay.log"
    for line in log.read_text().splitlines() if log.exists() else []:
        m = re.search(r"\[\s*(\d+) ms\] checkpoint (\S+)", line)
        if m and m.group(2) not in times:
            times[m.group(2)] = int(m.group(1)) / 1000
    return times


def matches(script: Path, capture: Path) -> bool:
    """The script is the one the capture was made with: same checkpoints, same gaps."""
    if not script.exists():
        return False
    cap = capture_times(capture)
    steps, _, names = translate(script, 0.0, capture=capture)
    ours = {x.split(":shot:")[1]: float(x.split(":")[0]) for x in steps.split(";") if ":shot:" in x}
    common = [n for n in names if n in cap]
    if not common or len(common) < len(names):
        return False
    offset = cap[common[0]] - ours[common[0]]
    return all(abs(cap[n] - ours[n] - offset) <= 0.3 for n in common)


def script_for(sc: dict, capture: Path) -> tuple[Path, str]:
    """The script to replay: the one matching the capture (the scenario's own,
    the copy kept with the capture, or the autoplay one it was made with)."""
    own = Path(sc["script"])
    for cand in (own, capture / "input.script", REFERENCE / "autoplay/scripts" / own.name, REFERENCE / "autoplay" / own.name):
        if matches(cand, capture):
            return cand, "" if cand == own else f"replays {cand.parent.name}/{cand.name}, the script the capture was made with"
    return own, "the script and the original's capture are out of sync"


def run_swiftdune(run: str, steps: str, seconds: float, cd: bool, saves: Path | None) -> Path:
    env = dict(os.environ, DUNE_IDLE_SECONDS=os.environ.get("DUNE_IDLE_SECONDS", "0"))
    if cd:
        env["DUNE_CD"] = "1"
    if saves:
        env["DUNE_SAVE_IN"] = str(saves)
    last = max(float(x.split(":")[0]) for x in steps.split(";"))
    for attempt in range(2):
        subprocess.run([str(HERE / "scripts/sim_run.sh"), run, str(int(seconds) + 1), "DUNE_START=game",
                        f"DUNE_SCRIPT={steps}"], cwd=HERE, env=env, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # A run whose log stops early (the simulator's launch host died) runs again once.
        log = SHOTS / run / "dune-ios.log"
        times = [float(m) for m in re.findall(r"harness ([0-9.]+)s", log.read_text())] if log.exists() else []
        if times and max(times) >= last - 0.01:
            break
        print(f"  the run stopped early ({max(times) if times else 0:.0f} of {last:.0f} s); again", flush=True)
    return SHOTS / run


def score_rows(sc_name: str, pairs: list[tuple[str, Path, Path]], img: Path, region=(0, 0, 320, 200)) -> list[dict]:
    rows = []
    for label, orig_png, ours_png in pairs:
        a, b = ref.load(orig_png), ref.load(ours_png)
        if a is None or b is None:
            rows.append({"checkpoint": label, "score": None, "img": "",
                         "note": "no original capture" if a is None else "SwiftDune did not reach it"})
            continue
        s, heat = ref.score(a, b, ref.cursor_box(orig_png), region)
        path = img / f"{sc_name}-{label}.png"
        ref.sheet(a, b, heat, path)
        rows.append({"checkpoint": label, "score": s, "img": f"img/{path.name}"})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--out", default=str(Path.home() / "dune-serve/cryo-dune-20260922/fidelity-swiftdune"))
    ap.add_argument("--offset", type=float, default=2.0, help="seconds from game start to the script's time 0")
    args = ap.parse_args()
    out = Path(args.out)
    img = out / "img"
    img.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((FIDELITY / "scenarios.json").read_text())
    # The floppy scenarios only: the manifest's CD ones ("data": "cd") are the
    # ScummVM harness's; SwiftDune's CD build is scored by CD_SCENARIOS below.
    scenarios = [dict(sc) for sc in manifest["scenarios"] if sc.get("data", "floppy") != "cd"]
    for sc in scenarios:
        if sc.get("type") == "flight":
            # The ScummVM report pairs landscape frames by number; SwiftDune
            # runs the original's own flight script instead, every 10th frame.
            sc["script"] = REFERENCE / "autoplay/scripts/flight-frames.script"
            sc["title"] += " (the original's clicks; every 10th frame)"
            sc["every"] = 10
        else:
            sc["script"] = FIDELITY / sc["script"]
    scenarios += CD_SCENARIOS
    results = []
    for sc in scenarios:
        if args.only and sc["name"] not in args.only:
            continue
        print(f"scenario {sc['name']}", flush=True)
        orig = CAPTURES / sc["original"]
        run = f"fid-{sc['name']}"
        script, note = (Path(sc["script"]), "") if sc.get("prelude_in_script") else script_for(sc, orig)
        if note:
            print(f"  {note}", flush=True)
            sc["title"] += f" ({note})"
        steps, seconds, names = translate(script, args.offset, skip_prelude=sc.get("prelude_in_script", False),
                                          capture=orig)
        if sc.get("every"):
            keep = set(names[::sc["every"]]) | {n for n in names if not n.startswith("f")}
            steps = ";".join(s for s in steps.split(";") if ":shot:" not in s or s.split(":shot:")[1] in keep)
            names = [n for n in names if n in keep]
        saves = FIDELITY / sc["saves"] if sc.get("saves") else None
        ours = run_swiftdune(run, steps, seconds, sc.get("cd", False), saves)
        pairs = [(n, orig / f"{n}.png", ours / f"{n}.png") for n in names]
        rows = score_rows(sc["name"], pairs, img)
        mean = sum(r["score"] or 0.0 for r in rows) / len(rows) if rows else 0.0
        reached = sum(1 for r in rows if r["score"] is not None)
        results.append({"name": sc["name"], "title": sc["title"], "score": mean, "rows": rows,
                        "reached": reached, "total": len(rows), "cd": bool(sc.get("cd"))})
        print(f"  {mean:.1f}% ({reached}/{len(rows)} checkpoints reached)", flush=True)
    commit = subprocess.run(["git", "log", "-1", "--format=%h %s"], cwd=HERE, capture_output=True, text=True).stdout.strip()
    floppy = [r for r in results if not r["cd"]]
    cd = [r for r in results if r["cd"]]
    overall = sum(r["score"] for r in floppy) / len(floppy) if floppy else 0.0
    overall_cd = sum(r["score"] for r in cd) / len(cd) if cd else 0.0
    history_path = out / "history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    if not args.only:
        history.append({"date": datetime.datetime.now().isoformat(timespec="minutes"), "commit": commit,
                        "overall": round(overall, 2), "overall_cd": round(overall_cd, 2), "scenarios": {r["name"]: round(r["score"], 2) for r in results}})
        history_path.write_text(json.dumps(history, indent=1))
    (out / "results.json").write_text(json.dumps(results, indent=1))
    write_html(out, results, overall, overall_cd, history, commit)
    print(f"floppy {overall:.1f}%  CD {overall_cd:.1f}%  report: {out / 'index.html'}")
    return 0


def write_html(out: Path, results: list, overall: float, overall_cd: float, history: list, commit: str) -> None:
    def table(rs):
        return "".join(f'<tr><td><a href="#{r["name"]}">{html.escape(r["name"])}</a></td><td>{html.escape(r["title"])}</td>'
                       f'<td>{r["reached"]}/{r["total"]}</td><td>{ref.bar(r["score"])}</td></tr>' for r in rs)
    head = "<tr><th>scenario</th><th>what</th><th>reached</th><th>score</th></tr>"
    floppy_rows = table([r for r in results if not r["cd"]])
    cd_rows = table([r for r in results if r["cd"]])
    names = "".join(f"<th>{html.escape(r['name'])}</th>" for r in results)
    hist = "".join(f"<tr><td>{h['date']}</td><td>{html.escape(h.get('commit', '')[:7])}</td><td><b>{h['overall']}</b></td><td><b>{h.get('overall_cd', '')}</b></td>"
                   + "".join(f"<td>{h['scenarios'].get(r['name'], '')}</td>" for r in results) + "</tr>"
                   for h in reversed(history[-20:]))
    detail = []
    for r in results:
        cells = []
        for it in sorted(r["rows"], key=lambda x: (x["score"] is not None, x["score"] or 0)):
            pic = (f'<a href="{it["img"]}"><img src="{it["img"]}" loading="lazy" alt="{html.escape(it["checkpoint"])}"></a>'
                   if it["img"] else f'<div class="none">{html.escape(it.get("note", ""))}</div>')
            cells.append(f'<div class="cp"><div class="h">{html.escape(it["checkpoint"])} {ref.bar(it["score"])}</div>{pic}</div>')
        detail.append(f'<h2 id="{r["name"]}">{html.escape(r["name"])}: {r["score"]:.1f}%</h2><p>{html.escape(r["title"])}. '
                      'Worst first. Each row: the original | SwiftDune | the difference (red; the original\'s cursor '
                      'masked in blue).</p>' + "".join(cells))
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>SwiftDune fidelity</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{{color-scheme:dark;--bg:#16181c;--fg:#e6e6e6;--line:#333;--link:#9cf;--bad:#e88}}
body{{font-family:-apple-system,Helvetica,sans-serif;background:var(--bg);color:var(--fg);margin:16px;max-width:1000px}}
table{{border-collapse:collapse;display:block;overflow-x:auto}} td,th{{padding:4px 8px;border-bottom:1px solid var(--line);text-align:left;font-size:14px}}
.big{{font-size:44px;font-weight:700}} .bar{{position:relative;width:180px;height:16px;background:#2a2d33;display:inline-block;vertical-align:middle}}
.bar div{{height:100%}} .bar span{{position:absolute;left:6px;top:0;font-size:12px;line-height:16px}}
.cp{{margin:10px 0}} .cp img{{width:100%;max-width:968px;image-rendering:pixelated;border:1px solid var(--line)}}
.h{{font-size:13px;margin-bottom:3px}} .miss,.none{{color:var(--bad)}} .none{{font-size:13px}} a{{color:var(--link)}}
</style></head><body>
<h1>SwiftDune (iOS): how close it is to the original</h1>
<p>Each scenario is played with the same clicks by the original game (on the Spice86 emulator, headless and silent)
and by SwiftDune in the iOS simulator (iPhone 14 Pro, iOS 16.4). Each checkpoint scores the share of pixels within
tolerance of the original's, with the original's mouse cursor left out. A checkpoint SwiftDune did not reach counts
as 0. Build: {html.escape(commit)}.</p>
<h2>Floppy: SwiftDune floppy vs the original floppy DUNEPRG.EXE</h2>
<p>The ScummVM engine's fidelity scenarios and captures.</p>
<div class="big">{overall:.1f}%</div>
<table>{head}{floppy_rows}</table>
<h2>CD: SwiftDune CD vs the original CD DNCDPRG.EXE</h2>
<div class="big">{overall_cd:.1f}%</div>
<table>{head}{cd_rows}</table>
<h2>History</h2><table><tr><th>run</th><th>build</th><th>floppy</th><th>CD</th>{names}</tr>{hist}</table>
{''.join(detail)}
<p>Generated {datetime.datetime.now():%Y-%m-%d %H:%M} by scripts/swiftdune_fidelity.py (dune-ios-swift).</p>
</body></html>"""
    (out / "index.html").write_text(page)


if __name__ == "__main__":
    sys.exit(main())
