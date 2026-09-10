#!/usr/bin/env python3
"""Recover the effect of each individual upgrade, offline, from a finished session.

Outcomes are logged once per round, so a round in which someone bought three
lanes yields one before/after pair and the three purchases are indistinguishable
inside it. The tempting fix is to recompute metrics inside the game after every
purchase, which would put an analysis-time need into the round loop and the
logging path. This does it from outside instead.

`network_links.csv` and `parameters.json` describe the board completely, so the
routing model can be rebuilt here and the session replayed link by link: start
from the network as the round opened, apply that round's purchases one at a time
in the order they were chosen, and solve every rider's route after each one. The
difference between consecutive steps is that one upgrade's marginal effect, for
the participant and for the city.

Because it reads only what is already on disk, it works on every session ever
recorded, and it cannot affect the game, the schema or determinism.

    python tools/replay_upgrades.py <session folder>
    python tools/replay_upgrades.py --latest
    python tools/replay_upgrades.py --all --kind study

Nothing is written into the session folder: the game's own codebook check reads
that folder back and reports files it does not describe, and an analysis output
is not session data. Results land in a `replays/` folder beside the sessions.

The replay is checked against the log before it is trusted. Every round's start
and end state is recomputed and compared with what the game recorded for the
players and for all 99 residents; the report leads with that comparison. If the
endpoints do not reproduce, the steps between them are not evidence either, and
the run exits non-zero.

Standard library only, so it needs no install on a lab machine.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from heapq import heappop, heappush
from pathlib import Path

# Floating point written through CSV and back, then re-derived by a different
# implementation in a different language. Loose enough not to trip on the last
# decimal place, tight enough that a genuinely different route cannot hide
# inside it (the closest pair of alternative routes in this network differ by
# far more than this in every metric).
TOLERANCE = 0.001

# Raw stress moves on a smaller scale than the other two, so the game gives it
# its own threshold (GameManager.BENEFIT_EPSILON_STRESS). Sessions written
# before that value was exported carry only the other two in parameters.json,
# hence the fallback.
DEFAULT_EPSILON_STRESS = 0.001

# The safety score normalises a route's stress against that same route fully
# unimproved, so an untouched route always reads 50 whatever its length
# (Player.SAFETY_TARGET_DEFICIT, and design doc 3.6 for why a flat scale cannot
# work). Not in parameters.json, and structural rather than tunable.
SAFETY_TARGET_DEFICIT = 50.0

LEVEL_NAMES = {0: "unimproved", 1: "painted", 2: "protected"}


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


def number(row: dict, key: str, default=None):
    raw = (row.get(key) or "").strip()
    if raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def canonical(a: str, b: str) -> str:
    """The undirected form of a link ID, lower endpoint first.

    Matches CityNetwork.canonical_link_id. Every table already stores links this
    way, but a route is walked in a direction, so the two halves of an edge have
    to collapse to one key before anything can be looked up.
    """
    ax, ay = (int(v) for v in a.split(","))
    bx, by = (int(v) for v in b.split(","))
    if ax < bx or (ax == bx and ay < by):
        return "%d,%d-%d,%d" % (ax, ay, bx, by)
    return "%d,%d-%d,%d" % (bx, by, ax, ay)


# --- The model, rebuilt from the exported network -------------------------


class Model:
    """The routing model of design doc 3.1, rebuilt from files alone.

        effective_time  = base_time x time_factor[level]
        impedance       = effective_time x (1 + alpha x beta x base_stress)

    Every constant comes from parameters.json or network_links.csv, so a session
    played on a different build replays under its own numbers rather than under
    whatever this script was written against.
    """

    def __init__(self, links: list[dict], params: dict) -> None:
        self.links: dict[str, dict] = {}
        self.adjacency: dict[str, list[tuple[str, str]]] = {}
        self.initial_level: dict[str, int] = {}

        for row in links:
            lid = row["link_id"]
            a, b = row["from_node"], row["to_node"]
            self.links[lid] = {
                "a": a,
                "b": b,
                "base_time": float(row["base_time_min"]),
                "base_stress": float(row["base_stress"]),
                "beta_painted": float(row["beta_painted"]),
                "length_m": float(row["length_m"]),
                "cost_painted": float(row["cost_painted"]),
                "cost_protected": float(row["cost_protected"]),
            }
            self.initial_level[lid] = int(row["initial_upgrade_level"])
            self.adjacency.setdefault(a, []).append((lid, b))
            self.adjacency.setdefault(b, []).append((lid, a))

        self.time_factor = [float(v) for v in params.get("time_factor_by_level", [1.0, 0.96, 0.92])]
        self.alpha_cautious = float(params.get("alpha_cautious", 3.0))
        self.alpha_average = float(params.get("alpha_average", 1.5))
        self.alpha_confident = float(params.get("alpha_confident", 0.4))
        self.beta_protected = {
            "cautious": float(params.get("beta_protected_cautious", 0.1)),
            "average": float(params.get("beta_protected_average", 0.2)),
            "confident": float(params.get("beta_protected_confident", 0.6)),
        }
        self.epsilon_time = float(params.get("benefit_epsilon_time", 0.01))
        self.epsilon_safety = float(params.get("benefit_epsilon_safety", 0.01))
        self.epsilon_stress = float(params.get("benefit_epsilon_stress", DEFAULT_EPSILON_STRESS))

    def beta_protected_for_alpha(self, alpha: float) -> float:
        """Banded by midpoint, as PersonalityConfig does, rather than by exact
        float equality: alpha is one of three constants and never changes at
        runtime, so the midpoints are unambiguous."""
        if alpha >= (self.alpha_cautious + self.alpha_average) / 2.0:
            return self.beta_protected["cautious"]
        if alpha >= (self.alpha_average + self.alpha_confident) / 2.0:
            return self.beta_protected["average"]
        return self.beta_protected["confident"]

    def beta(self, lid: str, level: int, alpha: float) -> float:
        if level == 1:
            return self.links[lid]["beta_painted"]
        if level == 2:
            return self.beta_protected_for_alpha(alpha)
        return 1.0

    def effective_time(self, lid: str, level: int) -> float:
        factor = self.time_factor[max(0, min(level, len(self.time_factor) - 1))]
        return self.links[lid]["base_time"] * factor

    def impedance(self, lid: str, level: int, alpha: float) -> float:
        link = self.links[lid]
        return self.effective_time(lid, level) * (
            1.0 + alpha * self.beta(lid, level, alpha) * link["base_stress"]
        )

    def coverage_pct(self, state: dict[str, int]) -> float:
        if not state:
            return 0.0
        upgraded = sum(1 for level in state.values() if level > 0)
        return 100.0 * upgraded / len(state)

    def start_state(self) -> dict[str, int]:
        return dict(self.initial_level)


def find_route(model: Model, state: dict[str, int], start: str, goal: str, alpha: float):
    """Dijkstra on impedance, as Dijkstra.gd runs it: settle cheapest first,
    stop at the goal, relax strictly (`<`), and sum effective_time along the
    reconstructed path for travel time."""
    dist = {start: 0.0}
    prev: dict[str, tuple[str, str]] = {}
    visited: set[str] = set()
    heap = [(0.0, start)]

    while heap:
        cost, node = heappop(heap)
        if node in visited:
            continue
        visited.add(node)
        if node == goal:
            break
        for lid, neighbour in model.adjacency.get(node, ()):
            if neighbour in visited:
                continue
            new_cost = cost + model.impedance(lid, state[lid], alpha)
            if new_cost < dist.get(neighbour, math.inf):
                dist[neighbour] = new_cost
                prev[neighbour] = (lid, node)
                heappush(heap, (new_cost, neighbour))

    if goal not in dist:
        return None

    links: list[str] = []
    travel_time = 0.0
    node = goal
    while node != start:
        lid, previous = prev[node]
        links.append(lid)
        travel_time += model.effective_time(lid, state[lid])
        node = previous
    links.reverse()
    return {"links": links, "travel_time_min": travel_time, "impedance": dist[goal]}


def ride(model: Model, state: dict[str, int], home: str, work: str, alpha: float) -> dict:
    """One rider's outcome on the network as it currently stands."""
    route = find_route(model, state, home, work, alpha)
    if route is None:
        return {"links": [], "travel_time_min": 0.0, "impedance": 0.0,
                "stress": 0.0, "safety": 100.0}

    stress = 0.0
    unimproved = 0.0
    for lid in route["links"]:
        link = model.links[lid]
        exposure = link["base_stress"] * link["base_time"]
        # Weighted by base_time, never effective_time: stress exposure scales
        # with the road ridden, not with how fast the infrastructure lets you
        # cover it. Weighting by the faster time would count the upgrade twice.
        stress += model.beta(lid, state[lid], alpha) * exposure
        unimproved += exposure

    safety = 100.0 if unimproved <= 0.0 else max(
        0.0, 100.0 - (stress / unimproved) * SAFETY_TARGET_DEFICIT)
    route["stress"] = stress
    route["safety"] = safety
    return route


def city_metrics(model: Model, state: dict[str, int], residents: list[dict],
                 seats: list[dict]) -> dict:
    """The city averages as GameManager computes them: over the residents AND
    the human players. The seats are part of the city they are investing in, so
    leaving them out here would not reproduce the logged figure."""
    everyone = residents + seats
    count = float(len(everyone)) or 1.0
    return {
        "city_avg_travel_time_min": sum(r["travel_time_min"] for r in everyone) / count,
        "city_avg_safety": sum(r["safety"] for r in everyone) / count,
        "city_avg_stress": sum(r["stress"] for r in everyone) / count,
        "city_coverage_pct": model.coverage_pct(state),
    }


def benefit_metrics(model: Model, now: list[dict], baseline: list[dict]) -> dict:
    """How many residents are better off than on the untouched Round-1 network.

    Time, safety and stress are counted separately and never combined, and the
    reference is the Round-1 baseline rather than the previous step, matching
    `benefit_metric` and `benefit_reference` in parameters.json.
    """
    time_improved = safety_improved = stress_improved = 0
    time_net = safety_net = stress_net = 0.0

    for after, before in zip(now, baseline):
        time_gain = before["travel_time_min"] - after["travel_time_min"]
        safety_gain = after["safety"] - before["safety"]
        stress_gain = before["stress"] - after["stress"]
        time_net += time_gain
        safety_net += safety_gain
        stress_net += stress_gain
        if time_gain > model.epsilon_time:
            time_improved += 1
        if safety_gain > model.epsilon_safety:
            safety_improved += 1
        if stress_gain > model.epsilon_stress:
            stress_improved += 1

    total = float(len(now)) or 1.0
    return {
        "residents_time_improved": time_improved,
        "residents_time_improved_pct": 100.0 * time_improved / total,
        "residents_safety_improved": safety_improved,
        "residents_safety_improved_pct": 100.0 * safety_improved / total,
        "residents_stress_improved": stress_improved,
        "residents_total_time_saved_min": time_net,
        "residents_total_safety_gained": safety_net,
        "residents_total_stress_reduced": stress_net,
    }


# --- What the session recorded --------------------------------------------


class Session:
    """The parts of a session folder this tool needs, in the shape it needs."""

    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.params = read_json(folder / "parameters.json") or {}
        self.rounds = read_csv(folder / "rounds.csv")
        self.upgrades = read_csv(folder / "upgrades.csv")
        self.decisions = read_csv(folder / "decisions.csv")
        self.residents = read_csv(folder / "residents.csv")
        self.model = Model(read_csv(folder / "network_links.csv"), self.params)

    @property
    def session_id(self) -> str:
        return str(self.params.get("session_id") or self.folder.name)

    @property
    def kind(self) -> str:
        return str(self.params.get("session_kind") or "unmarked")

    def round_numbers(self) -> list[int]:
        return sorted({int(r["round"]) for r in self.rounds if (r.get("round") or "").isdigit()})

    def seats(self, round_num: int) -> list[dict]:
        """The riders at the table this round, as home/work/alpha. Three in a
        group session, one otherwise; each keeps their own commute and their own
        stress sensitivity even where the budget is shared."""
        out = []
        for row in self.rounds:
            if int(row["round"]) != round_num:
                continue
            out.append({
                "player_num": row.get("player_num", "1"),
                "participant_id": row.get("participant_id", ""),
                "alpha": number(row, "alpha", 1.5),
                "home": row.get("home_node", ""),
                "work": row.get("work_node", ""),
                "row": row,
            })
        return sorted(out, key=lambda s: str(s["player_num"]))

    def resident_roster(self) -> list[dict]:
        """Home, work and alpha per simulated resident, taken from the first
        snapshot they appear in. The set is a fixed authored list, so one pass is
        enough and the order is the resident_index order every table uses."""
        seen: dict[int, dict] = {}
        for row in self.residents:
            idx = int(row["resident_index"])
            if idx in seen:
                continue
            seen[idx] = {
                "resident_index": idx,
                "home": row["home"],
                "work": row["work"],
                "alpha": number(row, "alpha", 1.5),
            }
        return [seen[i] for i in sorted(seen)]

    def logged_residents(self, round_num: int, phase: str) -> dict[int, dict]:
        out = {}
        for row in self.residents:
            if int(row["round"]) != round_num or row.get("phase") != phase:
                continue
            out[int(row["resident_index"])] = row
        return out

    def round_steps(self, round_num: int) -> list[dict]:
        """This round's purchases, in the order the participant chose them.

        upgrades.csv says what was committed to but carries no ordering column,
        and marginal effects are not additive, so the order matters: the second
        protected lane on a corridor is worth less than the first. decisions.csv
        does carry the order, so the two are joined on link_id and anything
        without a matching decision keeps its file position at the end.
        """
        order: dict[str, float] = {}
        for row in self.decisions:
            if int(row["round"]) != round_num:
                continue
            if (row.get("confirmed") or "0") not in ("1", "true", "True"):
                continue
            lid = canonical(*row["link_id"].split("-"))
            seq = number(row, "selection_order", math.inf)
            order[lid] = min(order.get(lid, math.inf), seq)

        steps = []
        for position, row in enumerate(self.upgrades):
            if int(row["round"]) != round_num:
                continue
            lid = canonical(*row["link_id"].split("-"))
            steps.append({
                "link_id": lid,
                "action": row.get("action", "upgrade"),
                "level": int(number(row, "level", 0)),
                "cost": number(row, "cost", 0.0),
                "sort": (order.get(lid, math.inf), position),
            })
        steps.sort(key=lambda s: s["sort"])
        return steps


# --- Replay ----------------------------------------------------------------


def apply_step(model: Model, state: dict[str, int], step: dict) -> None:
    """A purchase sets the link's level; a removal returns it to what the city
    started with, not to bare road, because the pre-existing lanes were never
    the participant's to demolish (CityNetwork.downgrade_link)."""
    lid = step["link_id"]
    if lid not in state:
        return
    if step["action"] == "removal":
        state[lid] = model.initial_level[lid]
    else:
        state[lid] = step["level"]


def solve(model: Model, state: dict[str, int], roster: list[dict],
          seats: list[dict]) -> tuple[list[dict], list[dict]]:
    residents = [ride(model, state, r["home"], r["work"], r["alpha"]) for r in roster]
    riders = [ride(model, state, s["home"], s["work"], s["alpha"]) for s in seats]
    return residents, riders


def replay(session: Session, rep: "Report") -> list[dict]:
    model = session.model
    roster = session.resident_roster()
    rows: list[dict] = []

    state = model.start_state()
    baseline_residents: list[dict] | None = None

    for round_num in session.round_numbers():
        seats = session.seats(round_num)
        if not seats:
            continue

        steps = session.round_steps(round_num)
        residents, riders = solve(model, state, roster, seats)
        if baseline_residents is None:
            # The static Prospect Theory reference: the untouched Round-1
            # network, captured once and never rolled forward (design doc 3.7).
            baseline_residents = residents
        verify(session, round_num, "before", residents, riders, seats, roster,
               city_metrics(model, state, residents, riders), rep)

        previous = snapshot(model, state, residents, riders, seats, baseline_residents)
        rows.extend(emit(session, round_num, 0, len(steps), None, previous, previous, 0.0))

        spent = 0.0
        for index, step in enumerate(steps, start=1):
            on_route_before = {
                str(s["player_num"]): step["link_id"] in previous["riders"][i]["links"]
                for i, s in enumerate(seats)
            }
            apply_step(model, state, step)
            residents, riders = solve(model, state, roster, seats)
            current = snapshot(model, state, residents, riders, seats, baseline_residents)
            spent += step["cost"] or 0.0
            rows.extend(emit(session, round_num, index, len(steps), step, current, previous,
                             spent, on_route_before))
            previous = current

        verify(session, round_num, "after", previous["residents"], previous["riders"],
               seats, roster, previous["city"], rep)

    return rows


def snapshot(model: Model, state: dict[str, int], residents: list[dict], riders: list[dict],
             seats: list[dict], baseline_residents: list[dict]) -> dict:
    return {
        "residents": residents,
        "riders": riders,
        "seats": seats,
        "city": city_metrics(model, state, residents, riders),
        "benefit": benefit_metrics(model, residents, baseline_residents),
    }


# --- Verification ----------------------------------------------------------


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.worst: float = 0.0
        self.checked: int = 0

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def compare(self, where: str, metric: str, computed: float, logged) -> None:
        if logged is None:
            return
        self.checked += 1
        gap = abs(computed - logged)
        self.worst = max(self.worst, gap)
        if gap > TOLERANCE:
            self.fail("%s: %s replays as %.4f, the log says %.4f."
                      % (where, metric, computed, logged))


def verify(session: Session, round_num: int, phase: str, residents: list[dict],
           riders: list[dict], seats: list[dict], roster: list[dict],
           city: dict, rep: Report) -> None:
    """Check the replayed state against what the game recorded at the same point.

    The middle of a round is not observed anywhere, so the only evidence that
    the steps are right is that the two ends of every round land exactly where
    the log says they did, for all 99 residents and not only the participant.
    """
    logged = session.logged_residents(round_num, phase)
    for i, resident in enumerate(roster):
        row = logged.get(resident["resident_index"])
        if row is None:
            continue
        where = "round %d %s, resident %d" % (round_num, phase, resident["resident_index"])
        rep.compare(where, "travel_time_min", residents[i]["travel_time_min"],
                    number(row, "travel_time_min"))
        rep.compare(where, "safety", residents[i]["safety"], number(row, "safety"))
        rep.compare(where, "stress", residents[i]["stress"], number(row, "stress"))
        rep.compare(where, "impedance", residents[i]["impedance"], number(row, "impedance"))
        route = "|".join(residents[i]["links"])
        if (row.get("route_links") or "") != route:
            rep.fail("%s: replayed route %s, the log says %s."
                     % (where, route, row.get("route_links")))

    # rounds.csv holds the player's state at the END of the round, so only the
    # "after" phase has a recorded counterpart to compare against.
    if phase != "after":
        return
    for i, seat in enumerate(seats):
        row = seat["row"]
        where = "round %d, seat %s" % (round_num, seat["player_num"])
        rep.compare(where, "travel_time_min", riders[i]["travel_time_min"],
                    number(row, "travel_time_min"))
        rep.compare(where, "safety", riders[i]["safety"], number(row, "safety"))
        rep.compare(where, "stress", riders[i]["stress"], number(row, "stress"))
        rep.compare(where, "impedance", riders[i]["impedance"], number(row, "impedance"))
        route = "|".join(riders[i]["links"])
        if (row.get("route_links") or "") != route:
            rep.fail("%s: replayed route %s, the log says %s."
                     % (where, route, row.get("route_links")))
        for metric in ("city_avg_travel_time_min", "city_avg_safety",
                       "city_avg_stress", "city_coverage_pct"):
            rep.compare(where, metric, city[metric], number(row, metric))


# --- Output ----------------------------------------------------------------

# One declaration, read by both the writer and the codebook, so a column cannot
# exist here without a description or survive being renamed without one. Same
# arrangement as LogSchema.gd, for the same reason.
COLUMNS: list[tuple[str, str]] = [
    ("session_id", "The session this replay came from."),
    ("session_kind", "What that session was for: study, pilot, test, or unmarked for folders written before the marker existed."),
    ("sitting_id", "The sitting the session belongs to; identical across a paired T1-then-T2 visit."),
    ("group_id", "The set of people who played together, in the group treatment."),
    ("participant_id", "The rider this row describes. Every seat gets its own row at every step, because each has their own commute and their own outcome even where the budget is shared."),
    ("player_num", "Seat number within the session, 1-based."),
    ("treatment", "0 = individual, 1 = individual plus city metrics, 2 = group discussion."),
    ("round", "1-based round number."),
    ("step", "Position within the round. 0 is the network as the round opened, before any of its purchases; 1..n are the purchases in the order they were chosen. Step 0 anchors the round and carries no marginal values."),
    ("n_steps", "How many purchases this round had, so a step can be read as 'the second of four'."),
    ("action", "'upgrade' for a purchase, 'removal' for an upgrade taken back off. Blank at step 0."),
    ("link_id", "The link this step acted on. Blank at step 0."),
    ("level", "The level the link was set to. For a removal, the level it was removed from."),
    ("level_name", "Readable form of the column above."),
    ("cost", "What this one step cost, in dollars."),
    ("cost_cumulative", "Dollars committed so far this round, including this step."),
    ("link_on_own_route", "1 if the link was on THIS rider's route immediately before the step. Whether the money was aimed at their own commute, decided one purchase at a time rather than averaged over the round."),
    ("travel_time_min", "This rider's travel time in minutes after the step."),
    ("safety", "This rider's safety score after the step. Per-route normalised, floor 50."),
    ("stress", "This rider's raw route stress after the step. Absolute exposure, not normalised, so it is not interchangeable with safety."),
    ("impedance", "Impedance of this rider's route after the step: the quantity Dijkstra minimised."),
    ("route_n_links", "Links in this rider's route after the step."),
    ("route_links", "This rider's route after the step, as link IDs, pipe separated."),
    ("route_changed", "1 if this step moved this rider onto a different route. The reroute is the mechanism the whole model turns on, and it is invisible in the per-round log when several purchases share a round."),
    ("travel_time_min_marginal", "Minutes THIS STEP saved this rider. Signed positive = improvement, as everywhere else. Blank at step 0."),
    ("safety_marginal", "Safety points this step gained this rider."),
    ("stress_marginal", "Raw stress this step removed from this rider's ride."),
    ("impedance_marginal", "Impedance this step removed from this rider's route."),
    ("city_avg_travel_time_min", "Mean travel time across residents and seats after the step."),
    ("city_avg_safety", "Mean safety across residents and seats after the step."),
    ("city_avg_stress", "Mean raw stress across residents and seats after the step."),
    ("city_coverage_pct", "Percentage of links carrying any upgrade after the step."),
    ("city_avg_travel_time_min_marginal", "Minutes this step took off the city average."),
    ("city_avg_safety_marginal", "Safety points this step added to the city average."),
    ("city_avg_stress_marginal", "Raw stress this step took off the city average."),
    ("residents_time_improved", "Residents faster than on the untouched Round-1 network, after this step."),
    ("residents_time_improved_pct", "The same as a percentage."),
    ("residents_safety_improved", "Residents safer than on the untouched Round-1 network, after this step."),
    ("residents_safety_improved_pct", "The same as a percentage."),
    ("residents_stress_improved", "Residents with lower raw route stress than at Round 1, after this step."),
    ("residents_time_improved_marginal", "Residents this step moved into the faster-than-baseline group. Can be negative: a reroute elsewhere in the city can take someone back out of it."),
    ("residents_safety_improved_marginal", "Residents this step moved into the safer-than-baseline group."),
    ("residents_total_time_saved_min", "Minutes saved summed across all residents versus Round 1. Excludes the seats, who are a different population."),
    ("residents_total_safety_gained", "Safety points gained summed across all residents versus Round 1."),
    ("residents_total_time_saved_min_marginal", "Resident-minutes THIS STEP generated for the city."),
    ("residents_total_safety_gained_marginal", "Resident safety points this step generated for the city."),
]

FILE_NOTES = {
    "marginal_effects.csv": "One row per rider per replay step. Step 0 is the network as the round opened; each later step is one purchase applied on top of the last, in the order it was chosen. The _marginal columns are that one purchase's effect. Derived entirely from the session folder by tools/replay_upgrades.py; it is not session data and does not live beside it.",
    "codebook.csv": "What every column in the file above means. Generated from the same declaration the writer uses.",
    "replay_report.txt": "Whether the replay reproduced the session's own recorded numbers. Read this before using the figures: the middle of a round is unobserved, so the evidence that the steps are right is that both ends of every round land exactly where the log says they did.",
}


def cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def emit(session: Session, round_num: int, step_index: int, n_steps: int, step, current: dict,
         previous: dict, spent: float, on_route_before: dict | None = None) -> list[dict]:
    """One row per seat for this step, with the city columns repeated across
    them exactly as rounds.csv repeats its own: they describe the session, not
    the person, and summing down them would count one city three times."""
    rows = []
    first = current["seats"][0]["row"] if current["seats"] else {}

    for i, seat in enumerate(current["seats"]):
        rider = current["riders"][i]
        was = previous["riders"][i]
        marginal = step_index > 0
        row = {
            "session_id": session.session_id,
            "session_kind": session.kind,
            "sitting_id": first.get("sitting_id", ""),
            "group_id": first.get("group_id", ""),
            "participant_id": seat["participant_id"],
            "player_num": seat["player_num"],
            "treatment": first.get("treatment", ""),
            "round": round_num,
            "step": step_index,
            "n_steps": n_steps,
            "action": step["action"] if step else "",
            "link_id": step["link_id"] if step else "",
            "level": step["level"] if step else "",
            "level_name": LEVEL_NAMES.get(step["level"], "") if step else "",
            "cost": step["cost"] if step else "",
            "cost_cumulative": spent if step else "",
            "link_on_own_route": (1 if on_route_before.get(str(seat["player_num"])) else 0)
                                 if (step and on_route_before) else "",
            "travel_time_min": rider["travel_time_min"],
            "safety": rider["safety"],
            "stress": rider["stress"],
            "impedance": rider["impedance"],
            "route_n_links": len(rider["links"]),
            "route_links": "|".join(rider["links"]),
            "route_changed": (1 if rider["links"] != was["links"] else 0) if marginal else "",
            "travel_time_min_marginal": (was["travel_time_min"] - rider["travel_time_min"]) if marginal else "",
            "safety_marginal": (rider["safety"] - was["safety"]) if marginal else "",
            "stress_marginal": (was["stress"] - rider["stress"]) if marginal else "",
            "impedance_marginal": (was["impedance"] - rider["impedance"]) if marginal else "",
        }
        for key in ("city_avg_travel_time_min", "city_avg_safety", "city_avg_stress",
                    "city_coverage_pct"):
            row[key] = current["city"][key]
        row["city_avg_travel_time_min_marginal"] = (
            previous["city"]["city_avg_travel_time_min"] - current["city"]["city_avg_travel_time_min"]
        ) if marginal else ""
        row["city_avg_safety_marginal"] = (
            current["city"]["city_avg_safety"] - previous["city"]["city_avg_safety"]
        ) if marginal else ""
        row["city_avg_stress_marginal"] = (
            previous["city"]["city_avg_stress"] - current["city"]["city_avg_stress"]
        ) if marginal else ""

        for key in ("residents_time_improved", "residents_time_improved_pct",
                    "residents_safety_improved", "residents_safety_improved_pct",
                    "residents_stress_improved", "residents_total_time_saved_min",
                    "residents_total_safety_gained"):
            row[key] = current["benefit"][key]
        for key in ("residents_time_improved", "residents_safety_improved",
                    "residents_total_time_saved_min", "residents_total_safety_gained"):
            row[key + "_marginal"] = (
                current["benefit"][key] - previous["benefit"][key]) if marginal else ""

        rows.append(row)
    return rows


def write_outputs(out_dir: Path, rows: list[dict], rep: Report, session: Session) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    header = [name for name, _ in COLUMNS]

    with (out_dir / "marginal_effects.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for row in rows:
            writer.writerow([cell(row.get(name)) for name in header])

    with (out_dir / "codebook.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "column", "description"])
        for name, note in FILE_NOTES.items():
            writer.writerow([name, "(whole file)", note])
        for name, desc in COLUMNS:
            writer.writerow(["marginal_effects.csv", name, desc])

    lines = [
        "Replay of %s" % session.session_id,
        "  %s, %s round(s), %s resident(s), network %s"
        % (session.params.get("treatment_label", "?"), session.params.get("total_rounds", "?"),
           session.params.get("num_residents", "?"), session.params.get("network_signature", "?")),
        "  session kind: %s" % session.kind,
        "",
        "Checked %d recorded values against the replay. Largest disagreement: %.6f."
        % (rep.checked, rep.worst),
    ]
    if rep.failures:
        lines.append("")
        lines.append("FAILED (%d). The replay does not reproduce this session, so the" % len(rep.failures))
        lines.append("marginal figures beside it are not evidence.")
        for line in rep.failures[:40]:
            lines.append("  %s" % line)
        if len(rep.failures) > 40:
            lines.append("  ... and %d more." % (len(rep.failures) - 40))
    else:
        lines.append("")
        lines.append("PASSED. Every round's start and end state reproduces exactly, for the")
        lines.append("players and for every resident, so the steps between them can be read.")
    for line in rep.warnings:
        lines.append("  %s" % line)
    (out_dir / "replay_report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("\n".join(lines))
    print("")
    print("Wrote %d rows to %s" % (len(rows), out_dir / "marginal_effects.csv"))


def replay_folder(folder: Path, out_root: Path) -> int:
    session = Session(folder)
    if not session.params:
        print("Cannot read %s/parameters.json." % folder, file=sys.stderr)
        return 2
    if not session.rounds or not session.model.links:
        # A finding about the session rather than a usage error, so it goes to
        # stdout beside the successful replays and stays in order with them.
        print("%s has no rounds.csv or no network_links.csv, so it cannot be replayed."
              % folder.name)
        print("An unfinished session keeps events.json only; there is nothing to reconstruct.")
        return 2

    rep = Report()
    if "benefit_epsilon_stress" not in session.params:
        rep.warn("parameters.json predates benefit_epsilon_stress; replayed with %s."
                 % DEFAULT_EPSILON_STRESS)
    rows = replay(session, rep)
    write_outputs(out_root / session.session_id, rows, rep, session)
    return 1 if rep.failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", nargs="?", type=Path, help="the session folder to replay")
    parser.add_argument("--latest", action="store_true",
                        help="replay the most recently written session instead")
    parser.add_argument("--all", action="store_true",
                        help="replay every session folder found")
    parser.add_argument("--sessions", type=Path, default=default_sessions_dir(),
                        help="where the session folders live")
    parser.add_argument("--out", type=Path, default=None,
                        help="where to write the results (defaults to ../replays beside them)")
    parser.add_argument("--kind", default="all",
                        help="with --all, which sessions to replay: all (default), or a comma "
                             "separated list of study, pilot, test, unmarked")
    args = parser.parse_args()

    out_root = args.out or (args.sessions.parent / "replays")

    if args.all:
        if not args.sessions.is_dir():
            print("No session folder at %s" % args.sessions, file=sys.stderr)
            return 2
        wanted = {k.strip() for k in args.kind.split(",")} if args.kind != "all" else None
        replayed = skipped = failed = 0
        for folder in sorted(p for p in args.sessions.iterdir() if p.is_dir()):
            params = read_json(folder / "parameters.json") or {}
            kind = str(params.get("session_kind") or "unmarked")
            if wanted is not None and kind not in wanted:
                continue
            code = replay_folder(folder, out_root)
            print("")
            if code == 2:
                skipped += 1
            elif code == 1:
                failed += 1
            else:
                replayed += 1
        print("%d session(s) replayed, %d failed verification, %d skipped as unreadable."
              % (replayed, failed, skipped))
        # An abandoned session in a corpus is expected, not a fault of the run,
        # so only a replay that contradicts its own log fails the whole sweep.
        return 1 if failed else 0

    folder = args.folder
    if folder is None or args.latest:
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
    return replay_folder(folder, out_root)


if __name__ == "__main__":
    sys.exit(main())
