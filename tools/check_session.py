#!/usr/bin/env python3
"""Validate one session folder, in seconds, while the participant is still there.

The aggregate tool checks a whole corpus, which is the right unit for analysis
and the wrong unit for a lab day: by the time it runs, weeks later, a session
that went wrong cannot be run again. This checks a single folder immediately
after it is written, when the remedy is still "ask them to sit back down".

    python tools/check_session.py <session folder>
    python tools/check_session.py --latest

Exit code 0 when the session is sound, 1 when anything failed, 2 when the folder
could not be read at all. Warnings alone do not fail the run.

Standard library only, so it needs no install on a lab machine.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

# Deltas are signed positive = improvement throughout (CLAUDE.md 3.7). Time,
# stress and impedance read baseline - now; safety reads now - baseline.
LOWER_IS_BETTER = ["travel_time_min", "stress", "impedance", "city_avg_travel_time_min"]
HIGHER_IS_BETTER = ["safety", "city_avg_safety"]

# Floating point written through CSV and back. Loose enough not to trip on the
# last decimal place, tight enough that a delta measured against the wrong
# reference cannot hide inside it.
TOLERANCE = 0.01


def default_sessions_dir() -> Path:
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata"
    else:
        base = Path.home() / ".local" / "share" / "godot" / "app_userdata"
    return base / "Transport Game" / "research_sessions"


def read_csv(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_json(path: Path):
    if not path.is_file():
        return None
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def number(row: dict, key: str):
    """A cell as a float, or None when it is blank or not a number.

    Blank is a real value in this schema: the share columns are deliberately
    empty rather than -1 when undefined, so a checker that read blank as zero
    would invent data.
    """
    raw = (row.get(key) or "").strip()
    if raw == "":
        return None
    try:
        return float(raw)
    except ValueError:
        return None


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def note(self, msg: str) -> None:
        self.notes.append(msg)


def check_files_present(folder: Path, rep: Report) -> None:
    """Every file the codebook describes should exist beside it.

    The expected list is read from codebook.csv rather than hard-coded here,
    because the game generates that codebook from the same column declarations
    the writers use. Hard-coding the list would mean this tool going stale the
    first time a writer is added.
    """
    codebook = read_csv(folder / "codebook.csv")
    if not codebook:
        rep.fail("codebook.csv is missing or empty, so the folder cannot describe itself.")
        return
    expected = {r["file"] for r in codebook if (r.get("column") or "") == "(whole file)"}
    present = {p.name for p in folder.iterdir() if p.is_file()}
    for name in sorted(expected - present):
        rep.fail("missing file: %s" % name)
    for name in sorted(present - expected):
        if name.endswith(".part"):
            rep.fail("%s is a half-finished write; the file beside it may be stale." % name)
        else:
            rep.warn("unexpected file, not described by the codebook: %s" % name)


def check_finished(folder: Path, rep: Report) -> None:
    events = read_json(folder / "events.json")
    if events is None:
        rep.fail("events.json is missing or is not valid JSON.")
        return
    kinds = [e.get("round") for e in events]
    if "FINAL" not in kinds:
        rep.fail("no FINAL row: the session never reached its end screen.")
    if "POST_SURVEY" not in kinds:
        rep.fail("no POST_SURVEY row: the closing survey was not completed.")
    if "PRE_SURVEY" not in kinds:
        rep.fail("no PRE_SURVEY row.")
    if not (folder / "summary.json").is_file():
        rep.fail("no summary.json: the session did not finish.")


def check_rounds(folder: Path, params: dict, rep: Report) -> None:
    rows = read_csv(folder / "rounds.csv")
    if not rows:
        rep.fail("rounds.csv has no rows.")
        return

    expected_rounds = int(params.get("total_rounds") or 0)
    seats = sorted({r.get("player_num") for r in rows})
    for seat in seats:
        seat_rows = [r for r in rows if r.get("player_num") == seat]
        played = sorted({r.get("round") for r in seat_rows})
        if expected_rounds and len(played) != expected_rounds:
            rep.fail("seat %s played %d round(s), expected %d."
                     % (seat, len(played), expected_rounds))

    for row in rows:
        where = "seat %s round %s" % (row.get("player_num"), row.get("round"))

        pid = (row.get("participant_id") or "").strip()
        if not pid:
            rep.fail("%s has no participant_id, so it cannot be joined to a person." % where)

        available = number(row, "budget_available")
        spent = number(row, "budget_spent")
        if available is not None and spent is not None and spent > available + TOLERANCE:
            rep.fail("%s spent %.0f of a %.0f budget." % (where, spent, available))
        if spent is not None and spent < -TOLERANCE:
            rep.fail("%s spent a negative amount (%.0f)." % (where, spent))

        for metric in LOWER_IS_BETTER:
            _check_delta(row, metric, where, invert=False, rep=rep)
        for metric in HIGHER_IS_BETTER:
            _check_delta(row, metric, where, invert=True, rep=rep)


def _check_delta(row: dict, metric: str, where: str, invert: bool, rep: Report) -> None:
    """A delta must be the Round-1 baseline compared with now, not the previous
    round (CLAUDE.md 3.7). Measuring it the other way is invisible in round 1,
    where the two agree, and wrong everywhere after."""
    now = number(row, metric)
    baseline = number(row, metric + "_baseline")
    delta = number(row, metric + "_delta")
    if now is None or baseline is None or delta is None:
        return
    expected = (now - baseline) if invert else (baseline - now)
    if abs(expected - delta) > TOLERANCE:
        rep.fail("%s: %s_delta is %.3f but baseline and current give %.3f."
                 % (where, metric, delta, expected))


def check_surveys(folder: Path, rep: Report) -> None:
    rows = read_csv(folder / "surveys.csv")
    if not rows:
        rep.fail("surveys.csv has no rows.")
        return
    for row in rows:
        seat = row.get("player_num")
        pre = [k for k in row if k.startswith("pre_") and (row[k] or "").strip() != ""]
        post = [k for k in row if k.startswith("post_") and (row[k] or "").strip() != ""]
        if not pre:
            rep.fail("seat %s has no pre-survey answers." % seat)
        if not post:
            rep.fail("seat %s has no post-survey answers." % seat)


def check_residents(folder: Path, params: dict, rep: Report) -> None:
    rows = read_csv(folder / "residents.csv")
    if not rows:
        rep.warn("residents.csv has no rows.")
        return
    expected = int(params.get("num_residents") or 0)
    seen = len({r.get("resident_index") for r in rows})
    if expected and seen != expected:
        rep.warn("residents.csv covers %d residents, parameters say %d." % (seen, expected))


def check_kind(params: dict, rep: Report) -> None:
    kind = (params.get("session_kind") or "").strip()
    if not kind:
        rep.warn("no session_kind recorded: this folder predates the marker.")
    elif kind != "study":
        rep.note("This is a %s session. It will not count as participant data." % kind.upper())


def check_folder(folder: Path) -> int:
    rep = Report()
    params = read_json(folder / "parameters.json")
    if params is None:
        print("Cannot read %s/parameters.json." % folder)
        print("Either this is not a session folder, or the session never started.")
        return 2

    check_kind(params, rep)
    check_files_present(folder, rep)
    check_finished(folder, rep)
    check_rounds(folder, params, rep)
    check_surveys(folder, rep)
    check_residents(folder, params, rep)

    print(folder.name)
    print("  %s, %s round(s), %s resident(s)"
          % (params.get("treatment_label", "?"), params.get("total_rounds", "?"),
             params.get("num_residents", "?")))
    for line in rep.notes:
        print("  %s" % line)
    print("")

    if rep.failures:
        print("FAILED (%d)" % len(rep.failures))
        for line in rep.failures:
            print("  %s" % line)
    if rep.warnings:
        print("Warnings (%d)" % len(rep.warnings))
        for line in rep.warnings:
            print("  %s" % line)
    if not rep.failures:
        print("PASSED. Budgets, deltas, surveys and files all check out."
              if not rep.warnings else
              "PASSED, with warnings above.")
        print("The participant can go.")
    else:
        print("")
        print("Do NOT treat this session as collected data without looking at the above.")
    return 1 if rep.failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", nargs="?", type=Path,
                        help="the session folder to check")
    parser.add_argument("--latest", action="store_true",
                        help="check the most recently written session instead")
    parser.add_argument("--sessions", type=Path, default=default_sessions_dir(),
                        help="where the session folders live, for --latest")
    args = parser.parse_args()

    folder = args.folder
    if args.latest or folder is None:
        if not args.sessions.is_dir():
            print("No session folder at %s" % args.sessions, file=sys.stderr)
            return 2
        candidates = [p for p in args.sessions.iterdir() if p.is_dir()]
        if not candidates:
            print("No sessions inside %s" % args.sessions, file=sys.stderr)
            return 2
        folder = max(candidates, key=lambda p: p.stat().st_mtime)

    if not folder.is_dir():
        print("Not a folder: %s" % folder, file=sys.stderr)
        return 2
    return check_folder(folder)


if __name__ == "__main__":
    sys.exit(main())
