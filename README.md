# nfrf_games — CycleCity

Games developed for the NFRF Exploration project "Social Innovation in Engineering for
Climate-Neutral Cities".

**Godot 4.6.3.** The game is GDScript only.

CycleCity is a **lab research game about cycling infrastructure investment**. A participant
plays a citizen-planner with a budget each round, upgrading roads in a fictional city with
painted bike lanes or protected tracks. Three rounds, $1,300,000 per round. After each round
every rider's route is re-solved and the personal and city-wide outcomes update.

The research question is whether people allocate investment differently acting alone versus
having to agree as a group. That makes **the data the product**: parameter values, logging
completeness and determinism matter more than polish.

---

## Reading order for a new developer

1. `scripts/PersonalityConfig.gd` — the three rider types (alpha), in 60 lines.
2. `scripts/CityNetwork.gd`, the `Link` class and `beta_for()` — the model.
3. `scripts/Player.gd`, the header block — how the safety score is derived, and why it is
   **not** 100 minus the sum of stress weights.
4. `scripts/GameManager.gd`, `_recalculate_and_end_round()` — the round loop.
5. `scripts/DataLogger.gd`, `on_round_ended()` — what one logged round contains.
6. `tools/README.md` — the log formats and the analysis pipeline.
7. `SCRIPTS.md`: one line per script, and which file to open for a given change.

---

## Architecture

```
GameManager           autoload singleton. Round flow, treatment, signals.
├── CityNetwork       the graph + Dijkstra on impedance (plain class, not a Node)
├── Player            one rider: budget, alpha, route cache, per-round log (plain class)
└── (per scene)
    DataLogger        Node, created by scenes/main.gd, writes the session folder
    UI scenes         connect to GameManager's signals
```

`scenes/main.tscn` is the main scene and `scenes/main.gd` coordinates everything: it owns the
menu and survey flow, stages upgrades before they are bought, and drives the map camera.

**`GameManager` is an autoload** (see `project.godot`), so it is reached as a global rather
than as a child node. `Audio` is the only other autoload.

**`DataLogger` is created per scene, not as an autoload.** `main.gd` does `DataLogger.new()`
and parents it to the scene. That is deliberate: one logger is one session, a session is one
scene, and a chained T1 into T2 sitting reloads the scene between halves. An autoloaded logger
survived that reload still connected to `round_ended`, and appended the second session's
rounds to the first session's file.

### Signals

```gdscript
signal round_started(round_num: int, budget: int)
signal round_ended(round_num: int, results: Dictionary)
signal game_over(final_results: Dictionary)
signal route_updated(player_id: String, route: Dictionary)
signal city_metrics_updated(metrics: Dictionary)   # T2/T3 only
```

### Starting a game

```gdscript
# alphas: one per seat. T1 and T2 pass a single-element array; T3 passes one per participant.
GameManager.start_game(
    [PersonalityConfig.ALPHA_AVERAGE],
    GameManager.Treatment.COLLECTIVE_INFO,
)
```

`Treatment` is `INDIVIDUAL` (T1), `COLLECTIVE_INFO` (T2) or `GROUP_DISCUSSION` (T3). Home and
work nodes come from the network; no node carries a participant-facing name.

### The guardrail on UI reads, stated honestly

The rule is that UI reaches state through signals and never reads it directly. **That is not
literally true today**, so do not be surprised when you find it broken: roughly 28 direct
property reads exist across seven UI scripts, concentrated in `CityGrid` and `GameHUD`
(`GameManager.network`, `.human_players`, `.ai_commuters`, `.total_rounds`, `.treatment`).

They are all **pull reads at build or refresh time** — the map asking the network what to draw
— and no UI script writes core state. Every per-round update still arrives by signal. This is
recorded rather than fixed because changing that many call sites is a real refactor with real
risk on a build that is about to collect data.

---

## The model in one page

```
effective_time  = base_time × time_factor(infra_level)
impedance(link) = effective_time × (1 + alpha × base_stress × beta)
```

Routing is **one Dijkstra run per rider per round on impedance**, and the path it returns *is*
the chosen route. There are no hardcoded routes and no detour probabilities.

Because it minimises **impedance and not time**, calming a road can move a rider onto a longer
but quieter one: their travel time goes up while their stress goes down. That is the detour
behaviour the model exists to produce, not a bug, and the round summary says so on screen.

| | |
|---|---|
| `base_time` | from the on-screen distance between nodes. Immutable at runtime. |
| `base_stress` | from the link's role in the network: 24 arterials near 0.82, 45 backstreets near 0.22. Immutable at runtime. |
| `beta` | infrastructure relief: 1.0 unimproved, then painted, then protected. **This is what the player buys.** |
| `alpha` | rider stress sensitivity, from the pre-survey: 0.4 confident, 1.5 average, 3.0 cautious. |

**Network:** 46 nodes, 69 undirected links. The base topology is the Sioux Falls research test
network (24 nodes, 38 links), extended in August 2026. Count them from `CityNetwork.edges`
rather than trusting any prose, this line included.

**Safety** is per-route normalised: `100 − 50 × (route stress ÷ that same route fully
unimproved)`. Its real range is **50 to 95, not 0 to 100** — an untouched route reads exactly
50 by construction. Do not reintroduce a flat "100 minus the sum of stress weights" formula.
It was tried, and it provably cannot make every unimproved route read low while letting a
fully protected one read high for every personality.

**Treatments change what is displayed, never the logic.** T1 personal only, T2 adds city
metrics, T3 is T2 with a group at one shared screen deciding out loud. City metrics are
computed in every treatment including T1, so T1's figures are usable as the counterfactual;
`city_metrics_shown` records whether they were actually on screen.

---

## Running it

```bash
# play it
godot --path .

# headless boot check (prints nothing when clean)
godot --headless --path .

# refresh the global class cache after adding a new class_name
godot --headless --path . --import
```

### Probes

There are no unit tests. There are **probes**: headless scenes that drive the real classes and
assert properties that were once broken. Each prints `FAILURES: n` and exits non-zero.

```bash
for p in participant_id group_id safety_stars round_summary survey_identity hud; do
  godot --headless --path . "res://tools/probe_$p.tscn"
done
```

| Probe | What it holds |
|---|---|
| `probe_participant_id` | the ID check character catches substitutions and transpositions |
| `probe_group_id` | group numbering, and that browsing the menu cannot burn numbers |
| `probe_safety_stars` | the star rating tracks the score, and the map's stress equals the model's |
| `probe_round_summary` | the round and end panels fit on screen **on the frame they appear** |
| `probe_survey_identity` | each seat gets its own colour and ID, and a survey does not hide itself |
| `probe_hud` | banner and hint behaviour, and that overlay text is legible on what is behind it |

When you change something a probe covers, **check the probe fails if you revert your fix**. A
probe that cannot fail is worse than no probe.

---

## The data

Sessions are written to `user://research_sessions/<SESSION-ID>/` as they happen: the folder
appears before round 1 and every round is flushed as it ends, so a crash mid-session still
leaves valid data for the rounds that finished.

Each folder holds `events.json` (the source of record) plus tidy CSVs for analysis:
`rounds.csv`, `decisions.csv`, `upgrades.csv`, `surveys.csv`, `residents.csv`,
`network_links.csv`, `network_nodes.csv`, `parameters.json` and `codebook.csv`.

Columns are declared once in `scripts/LogSchema.gd`, which both the writers and the codebook
read, so a column cannot exist without a description.

```bash
python tools/check_session.py <session folder>    # check one session, on the day
python tools/aggregate_logs.py --kind study       # combine many into one dataset
python tools/replay_upgrades.py <session folder>  # what each individual upgrade did
```

**`tools/README.md` is the reference for all of this** — formats, participant and group IDs,
schema versions, and how to rebuild the routing model from the exported network alone.

### One trap worth knowing before you rename anything

`events.json`'s field names are frozen. Three still say `credits_*`, from a budget that used to
be denominated in coins: `"credits_spent"`, `"credits_spent_cumulative"` and
`"credits_remaining"`. `LogSchema.COLUMN_SOURCE` translates them to `budget_*` for the CSVs.
The GDScript *variables* were renamed to `budget_*`; the quoted keys must not be. There is a
note at the declarations in `Player.gd`.

---

## Guardrails

Invariants, not suggestions.

1. **Treatment is display only.** Branch on treatment to decide what is shown, never to change
   routing, costs or metric maths.
2. **UI reads state through signals.** See the honest note above.
3. **Determinism.** The RNG is seeded at 42; no unseeded ordering or shuffles.
4. **Routing is Dijkstra output.** No hardcoded routes or detour probabilities.
5. **`base_time` and `base_stress` are immutable at runtime.** Upgrades change `beta` and
   `time_factor`.
6. **Logging is append-only and schema-stable.** Additive changes are fine; do not break the
   schema, and do not rewrite `events.json`'s field names.
7. **No magic numbers.** Alpha, beta, costs and thresholds each live in one config location.
   Colour lives only in `scripts/Palette.gd`, mirrored by hand into `resources/ui_theme.tres`
   because a `.tres` cannot read a GDScript constant.
8. **The visual layer reads the model, it never becomes it.** Stress colours, car counts and
   ratings must derive from model state and must never affect routing.

---

## Android

There is an Android export preset. `export_presets.cfg` is untracked, so it exists only on the
machine that made it. Three things cost real time and are worth not rediscovering:

- Godot 4.6 will not export Android without the gradle build
  (`--install-android-build-template`). The old prebuilt-APK path fails with a **blank** error.
- That blank error is usually the project setting `textures/vram_compression/import_etc2_astc`
  being off. Check it first.
- JDK 22 builds it, and `export/android/java_sdk_path` must be set in the editor settings or
  the export refuses to start.

`user://` is app-private on Android, so `SessionExporter` zips every session folder and reports
where it landed. **None of this has been verified on real hardware.**
