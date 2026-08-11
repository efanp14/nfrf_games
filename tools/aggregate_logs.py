#!/usr/bin/env python3
"""Combine every session folder into analysis-ready datasets.

The game writes one folder per session. That is the right shape for collecting
data and the wrong shape for analysing it: a single participant's data is spread
across three folders in two sittings (T1 and T2 run back to back, T3 separately
and usually on another machine), so nothing on disk holds all participant-rounds
and nothing links a person's individual play to the group session they later
took part in. This walks every folder and produces the files an analysis
actually starts from.

Standard library only, deliberately. This has to run on whatever machine the
study data ends up on, without a Python environment being set up first.

Usage:
    python aggregate_logs.py                      # read the default location
    python aggregate_logs.py --sessions DIR --out DIR
    python aggregate_logs.py --no-residents       # skip the largest file
    python aggregate_logs.py --wide-all           # every round column in the wide file

Outputs, written to --out (default: an "aggregated" folder beside the sessions):

    all_rounds.csv         every participant-round, all sessions (the primary
                           long-format dataset)
    all_upgrades.csv       every link bought or removed
    all_surveys.csv        one row per participant per session
    all_sessions.csv       the per-session summaries stacked
    all_residents.csv      every simulated resident, round and phase
    participants_wide.csv  one row per PERSON, their three sessions reunited
    codebook.csv           what every column means
    aggregate_report.txt   what was read, what was skipped, and what looks wrong
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

# Columns carried into participants_wide.csv for each treatment and round.
# A curated set rather than all seventy: the wide file exists to be opened in a
# spreadsheet, and 70 x 3 rounds x 3 treatments is not something anyone reads.
# Pass --wide-all for the unabridged version.
WIDE_ROUND_COLUMNS = [
    "travel_time_min", "travel_time_min_delta", "safety", "safety_delta",
    "stress_delta", "impedance_delta", "route_changed", "decision_time_s",
    "budget_spent", "n_upgrades", "n_upgrades_painted", "n_upgrades_protected",
    "own_route_spend_share", "own_route_spend_share_cumulative",
    "city_avg_travel_time_min_delta", "city_avg_safety_delta", "city_coverage_pct",
    "residents_time_improved_pct", "residents_safety_improved_pct",
]

# Per-treatment, not per-round.
WIDE_SESSION_COLUMNS = [
    "session_id", "chained_from_session_id", "treatment_ordinal",
    "alpha", "personality", "alpha_source",
]

TREATMENT_PREFIX = {"0": "t1", "1": "t2", "2": "t3"}


def default_sessions_dir() -> Path:
    """Where Godot puts this project's user data on each platform."""
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata"
    else:
        base = Path.home() / ".local" / "share" / "godot" / "app_userdata"
    return base / "Transport Game" / "research_sessions"


# --- reading -----------------------------------------------------------------

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


def partition_events(events) -> dict:
    """Split events.json by row kind.

    One array holds five different shapes of row, told apart by `round`, which
    is an int for a round and a string for every marker. Checking the type first
    is not optional here.
    """
    out = {"rounds": [], "pre": [], "post": [], "final": {}, "consent": {}}
    for e in events or []:
        r = e.get("round")
        if isinstance(r, bool):
            continue
        if isinstance(r, int):
            out["rounds"].append(e)
        elif r == "FINAL":
            out["final"] = e
        elif r == "PRE_SURVEY":
            out["pre"].append(e)
        elif r == "POST_SURVEY":
            out["post"].append(e)
        elif r == "CONSENT":
            out["consent"] = e
    return out


def rounds_from_events(events) -> list[dict]:
    """Reconstruct participant-round rows from events.json.

    A compatibility path, used only when rounds.csv is absent. That happens for
    sessions recorded before these CSVs existed, and, the case that will keep
    happening, for a session abandoned before its closing survey, since the
    CSVs are written at the true end of a session while events.json is written
    as soon as the last round finishes. Without this, an abandoned session would
    vanish from the aggregate entirely rather than showing up as incomplete.
    """
    parts = partition_events(events)
    alpha_source = {int(e.get("player_num", 0) or 0): e.get("alpha_source")
                    for e in parts["pre"]}
    rows = []
    for entry in parts["rounds"]:
        players = entry.get("players") or [None]
        upgrades = entry.get("upgrades") or []
        for i, p in enumerate(players):
            p = p or {}
            row = {
                "schema_version": "",
                "session_id": entry.get("session_id"),
                "group_id": entry.get("group_id"),
                "chained_from_session_id": entry.get("chained_from_session_id") or "",
                "participant_id": p.get("participant_id") or entry.get("participant_id"),
                "player_num": i + 1,
                "treatment": entry.get("treatment"),
                "treatment_ordinal": entry.get("treatment_ordinal"),
                "group_mode": entry.get("group_mode"),
                "num_players": len(players),
                "round": entry.get("round"),
                "alpha": p.get("alpha", entry.get("alpha")),
                "alpha_source": alpha_source.get(i + 1),
                "decision_time_s": entry.get("decision_time_s"),
                "budget_spent": entry.get("credits_spent"),
                "budget_remaining": entry.get("credits_remaining"),
                "n_upgrades": len(upgrades),
                "route_changed": p.get("route_changed", entry.get("route_changed")),
                "own_route_spend_share": p.get("group_spend_on_my_route_share"),
            }
            # (column, events.json field, top-level fallback). The raw log keeps
            # its original field names; the tables use the schema-2 ones.
            for col, src, fallback in (("travel_time_min", "time", "personal_time"),
                                       ("safety", "safety", "personal_safety"),
                                       ("stress", "stress", "personal_stress"),
                                       ("impedance", "impedance", "personal_impedance")):
                row[col] = p.get(src, entry.get(fallback))
                row[col + "_before"] = p.get(src + "_before")
                row[col + "_baseline"] = p.get(src + "_baseline")
                row[col + "_delta"] = p.get(src + "_delta")
            for col, src in (("city_avg_travel_time_min", "city_avg_time"),
                             ("city_avg_safety", "city_avg_safety"),
                             ("city_avg_stress", "city_avg_stress")):
                for suffix in ("", "_before", "_baseline", "_delta"):
                    row[col + suffix] = entry.get(src + suffix)
            for key, value in entry.items():
                if key.startswith("residents_") or key.startswith("city_coverage_pct"):
                    row[key] = value
            rows.append(row)
    return rows


def decisions_from_events(events) -> list[dict]:
    """Rebuild the selection-order table when decisions.csv is absent.

    Mirrors DataLogger._decisions_rows(). `confirmed` and `changed_or_removed`
    are derived, not recorded: neither can be known until the round is
    confirmed, since whether a pick survived is settled only by what the round
    ended up buying.
    """
    rows = []
    for entry in partition_events(events)["rounds"]:
        events_in_round = entry.get("interaction_events") or []
        if not events_in_round:
            continue
        confirmed_level = {str(u.get("link", "")): u.get("level")
                           for u in entry.get("upgrades") or []}
        confirmed_removal = {str(r.get("link", "")) for r in entry.get("removals") or []}
        links = [str(e.get("link", "")) for e in events_in_round]
        group_mode = bool(entry.get("group_mode"))
        for i, e in enumerate(events_in_round):
            link, action = links[i], str(e.get("action", ""))
            level = e.get("level")
            if action == "stage_removal":
                survived = link in confirmed_removal
            elif action == "unstage":
                survived = False
            else:
                survived = confirmed_level.get(link) == level
            rows.append({
                "session_id": entry.get("session_id"),
                "sitting_id": entry.get("sitting_id") or entry.get("session_id"),
                "group_id": entry.get("group_id"),
                "participant_id": "" if group_mode else entry.get("participant_id"),
                "treatment": entry.get("treatment"),
                "round": entry.get("round"),
                "decision_maker_id": entry.get("group_id") if group_mode
                                     else entry.get("participant_id"),
                "decision_maker_type": "group" if group_mode else "participant",
                "selection_order": i + 1,
                "t_s": e.get("t_s"),
                "action": action,
                "link_id": link,
                "level": level,
                "confirmed": survived,
                "changed_or_removed": link in links[i + 1:],
            })
    return rows


def upgrades_from_events(events) -> list[dict]:
    parts = partition_events(events)
    rows = []
    for entry in parts["rounds"]:
        group_mode = bool(entry.get("group_mode"))
        buyer = "" if group_mode else (entry.get("participant_id") or "")
        common = {
            "session_id": entry.get("session_id"),
            "group_id": entry.get("group_id"),
            "participant_id": buyer,
            "treatment": entry.get("treatment"),
            "round": entry.get("round"),
        }
        for u in entry.get("upgrades") or []:
            rows.append({**common, "action": "upgrade", "link_id": u.get("link"),
                         "level": u.get("level"), "cost": u.get("cost"),
                         "length_m": u.get("length_m"),
                         "base_time_min": u.get("base_time_min"),
                         "own_route": u.get("own_route"),
                         "on_new_route": u.get("on_new_route")})
        for r in entry.get("removals") or []:
            rows.append({**common, "action": "removal", "link_id": r.get("link"),
                         "level": r.get("from_level"), "cost": r.get("refund"),
                         "length_m": r.get("length_m"),
                         "base_time_min": r.get("base_time_min")})
    return rows


def surveys_from_events(events) -> list[dict]:
    """Flatten survey answers when surveys.csv is absent.

    Attitude items keep the same two-column treatment the game uses: "Don't
    know" is stored as the string "dk", and leaving it in the numeric column
    turns the whole variable into text in every statistics package.
    """
    parts = partition_events(events)
    by_player = {}
    for e in parts["pre"]:
        n = int(e.get("player_num", 0) or 0)
        row = by_player.setdefault(n, {})
        row.update({
            "session_id": e.get("session_id"), "group_id": e.get("group_id"),
            "participant_id": e.get("participant_id"), "player_num": n,
            "treatment": e.get("treatment"),
            "treatment_ordinal": e.get("treatment_ordinal"),
            "alpha": e.get("alpha"), "alpha_mean": e.get("alpha_mean"),
            "personality": e.get("personality"), "alpha_source": e.get("alpha_source"),
        })
        _flatten(row, "pre_", e.get("responses") or {})
    for e in parts["post"]:
        n = int(e.get("player_num", 0) or 0)
        row = by_player.setdefault(n, {
            "session_id": e.get("session_id"), "group_id": e.get("group_id"),
            "participant_id": e.get("participant_id"), "player_num": n,
            "treatment": e.get("treatment"),
        })
        _flatten(row, "post_", e.get("responses") or {})
    return [by_player[n] for n in sorted(by_player)]


def _flatten(row: dict, prefix: str, responses: dict) -> None:
    for key, value in responses.items():
        col = prefix + key
        if isinstance(value, str) and value == "dk":
            row[col] = ""
            row[col + "_dk"] = 1
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            row[col] = value
            row[col + "_dk"] = 0
        else:
            row[col] = value


def residents_from_json(blocks) -> list[dict]:
    rows = []
    for block in blocks or []:
        for phase in ("before", "after"):
            for r in block.get("residents_%s" % phase) or []:
                links = r.get("route_links") or []
                rows.append({
                    "session_id": block.get("session_id"),
                    "group_id": block.get("group_id"),
                    "treatment": block.get("treatment"),
                    "round": block.get("round"), "phase": phase,
                    "resident_index": r.get("resident_index"),
                    "home": r.get("home"), "work": r.get("work"),
                    "alpha": r.get("alpha"), "travel_time_min": r.get("time"),
                    "stress": r.get("stress"), "safety": r.get("safety"),
                    "impedance": r.get("impedance"), "n_links": len(links),
                    "route_links": "|".join(str(x) for x in links),
                })
    return rows


# --- writing -----------------------------------------------------------------

def write_union_csv(path: Path, tables: list[list[dict]]) -> int:
    """Stack tables that may not share a column set.

    Columns are unioned rather than fixed, and a row missing a column gets a
    blank cell. That is what lets a session recorded under an older build sit in
    the same file as a newer one: columns are only ever added, so the older rows
    are simply blank in the newer columns instead of the whole file refusing to
    concatenate. It also means this script never needs updating when a column is
    added to the game.
    """
    columns: list[str] = []
    seen = set()
    for rows in tables:
        for row in rows:
            for col in row:
                if col not in seen:
                    seen.add(col)
                    columns.append(col)
    path.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for rows in tables:
            for row in rows:
                writer.writerow({c: _cell(row.get(c)) for c in columns})
                total += 1
    return total


def _cell(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        # 1/0, matching LogSchema.csv_cell() since schema 2: the words load as
        # text in every statistics package and have to be recoded before use.
        return "1" if value else "0"
    if isinstance(value, (list, tuple)):
        return "|".join("" if v is None else str(v) for v in value)
    if isinstance(value, dict):
        return json.dumps(value)
    return value


# --- the wide file -----------------------------------------------------------

def derive_groups(tables: list[list[dict]]) -> tuple[dict, int]:
    """Work out which group each participant belongs to, and fill it in.

    The group is only asked for in the group treatment, where it ties a
    separately recorded discussion to the rounds it covers. Individual sessions
    leave it blank, so on their own they say nothing about who was grouped with
    whom. The group session does: it names its group and lists its members, so
    every one of those members can have their solo rows filled in afterwards.

    Rows filled this way are marked `group_id_derived = true`, because an
    inferred group and a recorded one are not the same evidence. A participant
    who never played a group session keeps a blank group, which is correct: no
    group was ever recorded for them.

    Returns the participant to group map and how many rows were filled.
    """
    known: dict[str, str] = {}
    for rows in tables:
        for row in rows:
            gid = str(row.get("group_id") or "").strip()
            pid = str(row.get("participant_id") or "").strip()
            if gid and pid:
                known.setdefault(pid, gid)

    filled = 0
    for rows in tables:
        for row in rows:
            if "group_id" not in row:
                continue
            recorded = str(row.get("group_id") or "").strip()
            if recorded:
                row["group_id_derived"] = False
                continue
            pid = str(row.get("participant_id") or "").strip()
            if pid and pid in known:
                row["group_id"] = known[pid]
                row["group_id_derived"] = True
                filled += 1
            else:
                row["group_id_derived"] = False
    return known, filled


def build_wide(round_rows: list[dict], survey_rows: list[dict],
               all_round_columns: bool) -> list[dict]:
    """One row per person, their sessions across both sittings side by side.

    Columns are prefixed by TREATMENT (t1_/t2_/t3_), never by treatment_ordinal.
    The ordinal is counted per machine, and T3 runs on a different computer from
    T1 and T2, so a group session usually reports ordinal 1, and keying on it would
    quietly overwrite a person's T1 columns with their T3 data.
    """
    people: dict[str, dict] = {}

    round_columns = WIDE_ROUND_COLUMNS
    if all_round_columns:
        seen, round_columns = set(), []
        skip = {"participant_id", "group_id", "session_id", "round", "treatment",
                "treatment_label", "player_num", "schema_version"}
        for row in round_rows:
            for col in row:
                if col not in seen and col not in skip:
                    seen.add(col)
                    round_columns.append(col)

    for row in round_rows:
        pid = str(row.get("participant_id") or "").strip()
        if not pid:
            continue
        prefix = TREATMENT_PREFIX.get(str(row.get("treatment")).strip())
        if prefix is None:
            continue
        person = people.setdefault(pid, {"participant_id": pid})
        # A non-empty group must win. setdefault alone would let a blank from an
        # individual session land first and lock out the real group that arrives
        # later on the group session's rows.
        if not person.get("group_id"):
            person["group_id"] = row.get("group_id")
        for col in WIDE_SESSION_COLUMNS:
            if row.get(col) not in (None, ""):
                person["%s_%s" % (prefix, col)] = row.get(col)
        rnd = str(row.get("round") or "").strip()
        if rnd:
            for col in round_columns:
                if col in row:
                    person["%s_r%s_%s" % (prefix, rnd, col)] = row.get(col)

    for row in survey_rows:
        pid = str(row.get("participant_id") or "").strip()
        if not pid:
            continue
        person = people.setdefault(pid, {"participant_id": pid})
        # A non-empty group must win. setdefault alone would let a blank from an
        # individual session land first and lock out the real group that arrives
        # later on the group session's rows.
        if not person.get("group_id"):
            person["group_id"] = row.get("group_id")
        prefix = TREATMENT_PREFIX.get(str(row.get("treatment")).strip(), "t?")
        for col, value in row.items():
            if col.startswith("pre_"):
                # The opening survey describes the person, not the session, and
                # is reused across their sessions. Keep the first non-empty
                # answer rather than one copy per treatment.
                if value not in (None, "") and not person.get(col):
                    person[col] = value
            elif col.startswith("post_"):
                # The closing survey is asked after every treatment and its
                # answers are about THAT session, so these do get a prefix.
                person["%s_%s" % (prefix, col)] = value

    for pid, person in people.items():
        played = [p for p in ("t1", "t2", "t3") if person.get("%s_session_id" % p)]
        person["treatments_played"] = "|".join(played)
        person["n_treatments"] = len(played)

    ordered = []
    for pid in sorted(people):
        person = people[pid]
        row = {"participant_id": person.pop("participant_id"),
               "group_id": person.pop("group_id", ""),
               "n_treatments": person.pop("n_treatments"),
               "treatments_played": person.pop("treatments_played")}
        row.update(person)
        ordered.append(row)
    return ordered


# --- main --------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sessions", type=Path, default=default_sessions_dir(),
                        help="folder holding the per-session directories")
    parser.add_argument("--out", type=Path, default=None,
                        help="where to write the combined files")
    parser.add_argument("--no-residents", action="store_true",
                        help="skip all_residents.csv, much the largest output")
    parser.add_argument("--wide-all", action="store_true",
                        help="put every round column in participants_wide.csv")
    args = parser.parse_args()

    sessions_dir: Path = args.sessions
    out_dir: Path = args.out or sessions_dir.parent / "aggregated"

    if not sessions_dir.is_dir():
        print("No session folder at %s" % sessions_dir, file=sys.stderr)
        print("Pass --sessions with the right path.", file=sys.stderr)
        return 1

    # Identified by what a folder CONTAINS, not by what it is called. Session
    # folders are named for the treatment, the participants and the time
    # (T1-p001-2026-08-10_1435), a scheme that has already changed once, so
    # matching on a name prefix would quietly stop finding older or newer runs.
    markers = ("events.json", "rounds.csv", "summary.json")
    folders = sorted(p for p in sessions_dir.iterdir()
                     if p.is_dir() and any((p / m).is_file() for m in markers))
    if not folders:
        print("No session folders inside %s" % sessions_dir, file=sys.stderr)
        print("(looking for directories containing %s)" % ", ".join(markers),
              file=sys.stderr)
        return 1

    rounds, decisions, upgrades, surveys, summaries, residents = [], [], [], [], [], []
    report: list[str] = []
    read_from_json: list[str] = []
    incomplete: list[str] = []
    codebook_source: Path | None = None

    for folder in folders:
        events = read_json(folder / "events.json")
        summary = read_json(folder / "summary.json")
        if summary is None:
            # summary.json is written only after the closing survey, so its
            # absence means the session did not finish.
            incomplete.append(folder.name)
        else:
            summaries.append(summary)

        r = read_csv(folder / "rounds.csv")
        if r:
            rounds.append(r)
            decisions.append(read_csv(folder / "decisions.csv"))
            upgrades.append(read_csv(folder / "upgrades.csv"))
            surveys.append(read_csv(folder / "surveys.csv"))
            if not args.no_residents:
                residents.append(read_csv(folder / "residents.csv"))
            if codebook_source is None and (folder / "codebook.csv").is_file():
                codebook_source = folder / "codebook.csv"
        elif events:
            read_from_json.append(folder.name)
            rounds.append(rounds_from_events(events))
            decisions.append(decisions_from_events(events))
            upgrades.append(upgrades_from_events(events))
            surveys.append(surveys_from_events(events))
            if not args.no_residents:
                residents.append(residents_from_json(read_json(folder / "residents.json")))
        else:
            report.append("  %s: no rounds.csv and no readable events.json, skipped"
                          % folder.name)

    out_dir.mkdir(parents=True, exist_ok=True)

    # Fill the group in on the individual sessions, which are not asked for it,
    # from the group session that names the same participant. Must run before
    # anything reads group_id, including the wide file and the report.
    group_map, group_filled = derive_groups(
        rounds + decisions + upgrades + surveys + residents)

    flat_rounds = [row for table in rounds for row in table]
    flat_surveys = [row for table in surveys for row in table]

    counts = {
        "all_rounds.csv": write_union_csv(out_dir / "all_rounds.csv", rounds),
        "all_decisions.csv": write_union_csv(out_dir / "all_decisions.csv", decisions),
        "all_upgrades.csv": write_union_csv(out_dir / "all_upgrades.csv", upgrades),
        "all_surveys.csv": write_union_csv(out_dir / "all_surveys.csv", surveys),
        "all_sessions.csv": write_union_csv(out_dir / "all_sessions.csv", [summaries]),
    }
    if not args.no_residents:
        counts["all_residents.csv"] = write_union_csv(
            out_dir / "all_residents.csv", residents)

    wide = build_wide(flat_rounds, flat_surveys, args.wide_all)
    counts["participants_wide.csv"] = write_union_csv(
        out_dir / "participants_wide.csv", [wide])

    if codebook_source is not None:
        (out_dir / "codebook.csv").write_text(
            codebook_source.read_text(encoding="utf-8"), encoding="utf-8")
        counts["codebook.csv"] = "copied from %s" % codebook_source.parent.name
    else:
        # Every session here predates the codebook, so there is nothing to copy.
        # Say so, rather than leaving a missing file to be puzzled over.
        counts["codebook.csv"] = "not written (no session folder contained one)"

    # --- the report ----------------------------------------------------------
    lines = ["Aggregated %d session folder(s) from %s" % (len(folders), sessions_dir),
             "Written to %s" % out_dir, ""]
    for name, n in counts.items():
        lines.append("  %-24s %s" % (name, "%d rows" % n if isinstance(n, int) else n))
    lines.append("")

    by_treatment: dict[str, int] = {}
    for row in flat_rounds:
        key = TREATMENT_PREFIX.get(str(row.get("treatment")).strip(), "unknown")
        by_treatment[key] = by_treatment.get(key, 0) + 1
    breakdown = ", ".join("%s=%d" % (k, v) for k, v in sorted(by_treatment.items()))
    lines.append("Participant-rounds by treatment: " + (breakdown or "none"))
    lines.append("")

    # Individual sessions are not asked for a group, so it is filled in here
    # from the group session naming the same person. Say so plainly: an inferred
    # group is weaker evidence than a recorded one, and group_id_derived marks
    # every affected row.
    lines.append("Group IDs: %d participant(s) mapped from their group session, "
                 "%d row(s) filled in" % (len(group_map), group_filled))
    ungrouped = sorted({str(r.get("participant_id") or "").strip()
                        for r in flat_rounds
                        if str(r.get("participant_id") or "").strip()
                        and not str(r.get("group_id") or "").strip()})
    if ungrouped:
        lines.append("  no group on record (never played a group session): "
                     + ", ".join(ungrouped))
    lines.append("")

    if read_from_json:
        lines.append("Read from JSON (no rounds.csv, recorded before the CSVs existed,")
        lines.append("or the session did not reach its closing survey):")
        lines += ["  %s" % s for s in read_from_json]
        lines.append("")
    if incomplete:
        lines.append("INCOMPLETE: no summary.json, so the session never finished.")
        lines.append("Their rounds are still included above; decide whether to keep them:")
        lines += ["  %s" % s for s in incomplete]
        lines.append("")

    # Same person, same treatment, twice: an ID was reused, and the wide file
    # will have silently kept only one of the two.
    seen_pt: dict[tuple, list] = {}
    for row in flat_rounds:
        pid = str(row.get("participant_id") or "").strip()
        if not pid:
            continue
        key = (pid, str(row.get("treatment")).strip())
        sid = str(row.get("session_id") or "")
        if sid not in seen_pt.setdefault(key, []):
            seen_pt[key].append(sid)
    dupes = {k: v for k, v in seen_pt.items() if len(v) > 1}
    if dupes:
        lines.append("DUPLICATE participant + treatment: an ID was used twice.")
        lines.append("participants_wide.csv keeps only one of each pair:")
        for (pid, treatment), sids in sorted(dupes.items()):
            lines.append("  %s treatment %s: %s" % (pid, treatment, ", ".join(sids)))
        lines.append("")

    played: dict[str, set] = {}
    groups: dict[str, set] = {}
    for row in flat_rounds:
        pid = str(row.get("participant_id") or "").strip()
        if not pid:
            continue
        played.setdefault(pid, set()).add(str(row.get("treatment")).strip())
        gid = str(row.get("group_id") or "").strip()
        if gid:
            groups.setdefault(gid, set()).add(pid)

    half_sittings = [p for p, t in played.items() if ("0" in t) != ("1" in t)]
    if half_sittings:
        lines.append("HALF SITTING: T1 and T2 are played back to back, so one without")
        lines.append("the other means the sitting was abandoned part-way:")
        lines += ["  %s (has %s)" % (p, ",".join(sorted(played[p]))) for p in sorted(half_sittings)]
        lines.append("")

    missing_solo = [p for p, t in played.items() if "2" in t and not ({"0", "1"} & t)]
    if missing_solo:
        lines.append("GROUP SESSION WITHOUT SOLO DATA: these people played T3 but have")
        lines.append("no T1/T2 on file. Most likely their folders are still on the other")
        lines.append("machine and have not been copied across. Without them the")
        lines.append("individual-versus-group comparison cannot be made for these people:")
        lines += ["  %s" % p for p in sorted(missing_solo)]
        lines.append("")

    lines.append("Participants: %d" % len(played))
    lines.append("Groups: %d" % len(groups))
    lines += report

    text = "\n".join(lines) + "\n"
    (out_dir / "aggregate_report.txt").write_text(text, encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
