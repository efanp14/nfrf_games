# Turning session logs into an analysis dataset

## Where the logs are

The game writes one folder per session, outside the repo, in Godot's user data
directory:

```
Windows   %APPDATA%\Godot\app_userdata\Transport Game\research_sessions\
macOS     ~/Library/Application Support/Godot/app_userdata/Transport Game/research_sessions/
Linux     ~/.local/share/godot/app_userdata/Transport Game/research_sessions/
```

From inside the editor, `Project > Open User Data Folder` goes to the same place.

Folders are named for the treatment, who played, and when, to the minute:

```
T1-p001-2026-08-10_1435
T3-p001_p002_p003-2026-08-10_1512
```

The time is local, matching a paper session log written in the room. Timestamps
inside the files are UTC, the audio manifest included. A `_2` suffix appears
only when two sessions land in the same minute under the same name.

A session is **one treatment**, so a participant playing T1 then T2 produces two
folders, not one.

Beside the session folders, and not one of them, sits `participant_ids.txt`. It
is described below.

## Participant IDs

`participant_id` is the only thing joining a person's sessions together, and
those sessions are on two machines: T1 and T2 on the individual machine, T3 on
the group one, days apart. The ID therefore has to travel between them, which in
practice means on a card.

The menu's **Generate** button issues one:

```
PCY-XA6
```

Six characters, stored without the hyphen as `PCYXA6`. Reading left to right:
the machine that issued it, four random characters, and a check character.

- **The alphabet is Crockford Base32**, the digits and letters minus I, L, O and
  U. A card read as `AIK` and one read as `A1K` reach the same participant,
  because I and L fold to 1 and O folds to 0 on entry. Case and hyphens are
  ignored, so `pcy-xa6`, `PCYXA6` and `PCY-XA6` are one person.
- **The check character catches typing errors**, which is the failure that
  matters: an ID mistyped at the group machine used to record a perfectly valid
  session belonging to nobody, leaving that person's individual sessions joined
  to nothing. Measured against the built implementation, it rejects **all**
  372,000 single-character substitutions and **all** 19,407 adjacent
  transpositions tested. The menu warns as soon as a bad ID is typed. It does
  not block, since the research team may bring a scheme of its own.
- **There is no timestamp in the ID.** It would double the length, and because
  the ID is a filename and a join key, two strings differing only by a timestamp
  would be two different people in every table. The time an ID was issued is in
  the roster instead.
- **The first character is the machine**, so an ID says where it was issued and
  two machines cannot issue the same one. It is derived from the device and
  cached in `machine_letter.txt`, so it survives reinstalling the game. Writing
  a single letter into that file forces it.

`participant_ids.txt` is the roster of everything this machine has issued, in
order, two lines each:

```
PCY-XA6
2026-08-27T19:02:11Z

PK4-M29
2026-08-27T19:41:03Z
```

It is written when the ID is issued, not when the session starts, so a card
written out for someone who never played is still recorded and never reused. It
is the way back to an ID whose card was lost. It travels inside the zip that
**Export All Sessions** produces.

Older IDs such as `p001` and `t01` are still valid and pass through exactly as
typed. Only IDs that verify as issued are normalised, so nothing already in the
data is rewritten.

`tools/probe_participant_id.tscn` re-runs the checks above:

```
godot --headless --path . res://tools/probe_participant_id.tscn
```

## Group IDs

The group treatment records a **group ID** as well: `PG01`, `PG02`, and so on,
the machine letter followed by the count on that machine. It is **assigned, not
typed** — the menu shows the group the session will be recorded under and there
is no field to edit.

Nothing anywhere parses the value. It does three jobs, and all three only need
it to be distinct:

- it is the `decision_maker_id` on group decision rows, since in that treatment
  the group decides rather than a person;
- `derive_groups` in `aggregate_logs.py` uses it to fill each member's
  individual sessions in, marking those rows `group_id_derived`;
- it goes into `audio_manifest.json`, which is what ties a discussion recorded
  on a separate device back to the rounds it covers. **Write it on the recorder
  before the session starts** — that is why the menu shows it at all.

Sequential rather than random, deliberately unlike a participant ID. A
participant ID crosses machines on a card and gets typed back in, so it is drawn
at random and carries a check character. A group ID never leaves the machine and
is never typed back; it has to be said aloud and written on a recorder, and
`PG03` is better at that than a random string.

The number is taken from the highest already used, read from `group_ids.txt` and
from the `group_id` in every session's `parameters.json`. The second source is
what matters: a group that actually played keeps its number even if the roster
is lost. A group ID that was shown but never played is only in the roster, so
deleting that line frees it again — which is why the roster says not to edit it.

Group IDs typed by hand under the older scheme (`g001`) are left alone and are
not part of the sequence.

`tools/probe_safety_stars.tscn` checks that what a participant sees agrees with
what the model computes. The star rating actually moves when a rider invests (an
untouched commute reads empty, a fully protected one reads full, the rating never
goes backwards, the single-link preview keeps its own separate scale, and the debug
readout still reports the raw logged score); and the map's effective stress -- the
stress-view colour, the car count, the car speed -- equals the model's for the rider
actually playing, across every link, level and personality:

```
godot --headless --path . res://tools/probe_safety_stars.tscn
```

`tools/probe_hud.tscn` checks the parts of the HUD that only exist while a round
is running: the round banner, the first-round hint, the selected-road highlight,
and whether anything drawn over the map can actually be read. That last one is a
measured WCAG contrast ratio, not an opinion -- the hint once shipped cream on
beige at 1.02:1, which is invisible:

```
godot --headless --path . res://tools/probe_hud.tscn
```

`tools/probe_survey_identity.tscn` checks that a survey names whose turn it is --
seat colour, seat number and participant ID -- so that in a group session the
right person answers. It also guards the rule that PostSurvey must not hide
itself when it emits:

```
godot --headless --path . res://tools/probe_survey_identity.tscn
```

`tools/probe_round_summary.tscn` checks that the round-summary and end-of-game
panels fit on screen and that the buttons which advance the session are reachable.
It measures on the frame a panel is shown rather than after layout settles,
because a group session was once stuck at round 2 with its Next Round button
pushed off the bottom of the screen:

```
godot --headless --path . res://tools/probe_round_summary.tscn
```

`tools/probe_group_id.tscn` checks the counting, the menu row, and the
lost-roster case.

## What one session folder holds

| File | What it is |
| --- | --- |
| `rounds.csv` | **One row per participant per round.** The main table. |
| `decisions.csv` | One row per link selection, in the order made. What was *done*, including picks later changed or withdrawn. |
| `upgrades.csv` | One row per link bought or removed. What was *committed to*. |
| `surveys.csv` | One row per participant, every survey item its own column. |
| `residents.csv` | One row per simulated resident per round per phase. |
| `network_links.csv` | The road network played on, one row per link: length, base time, base stress, what the city started with, and both upgrade prices. |
| `network_nodes.csv` | The junctions, with names and map positions. |
| `summary.csv` / `summary.json` | The whole session on one row. |
| `parameters.json` | The settings and network fingerprint this session ran under. |
| `codebook.csv` | What every file is, and what every column in the tables above means. |
| `events.json` / `residents.json` | The original records the tables are built from. |
| `audio_manifest.json` | Round start and end times, for lining a recording up against the decisions made in it. |

The JSON files are the source of record and are never rewritten. The CSVs are a
reshape of them, not a recalculation.

## Checking one session, on the day

```
python tools/check_session.py --latest
```

Run this the moment a session ends, while the participant is still in the
building. It reads one folder and checks the things that cannot be fixed later:
that the session actually finished, that every file the codebook describes is
present, that no round spent more than its budget, that every delta really is
measured against the Round-1 baseline, that both surveys were answered by every
seat, and that no half-written `.part` file was left behind.

It prints "The participant can go" or a list of what failed. Exit code 0 for
sound, 1 for failed, 2 for a folder it could not read, so it can be wired into a
script if you want. Pass a folder path instead of `--latest` to check a
particular session.

The aggregate tool below checks a whole corpus, which is the right unit for
analysis and the wrong one for a lab day: by the time it runs, a session that
went wrong cannot be run again.

## Combining sessions

A single participant's data spans **three folders across two sittings**: T1 and
T2 are played back to back and produce two folders, and T3 is a separate sitting
usually run on a different computer. Copy every folder into one place first,
including the ones from the other machine, then:

```
python tools/aggregate_logs.py
```

Standard library only, so no `pip install` is needed. Options:

```
--sessions DIR    where the per-session folders are (defaults to the path above)
--out DIR         where to write the results (defaults to ../aggregated)
--no-residents    skip all_residents.csv, much the largest output
--wide-all        put every round column in participants_wide.csv
--kind LIST       which sessions to include: all (default), or a comma
                  separated list of study, pilot, test, unmarked
```

**Use `--kind study` before analysing anything.** Development runs, playtests
and rehearsals write session folders that look exactly like participant data.
Every session now records what it was for, and the report opens with the
breakdown, so a corpus that mixes them says so instead of quietly averaging
them together. Folders written before the marker existed report `unmarked`;
treat those as development runs unless you know otherwise.

It produces:

| File | Shape |
| --- | --- |
| `all_rounds.csv` | Every participant-round, all sessions. **Start here.** Long format: one row per person per round, with treatment as a column. |
| `all_decisions.csv` | Every link selection, all sessions, in order. |
| `all_upgrades.csv` | Every purchase, all sessions. |
| `all_surveys.csv` | One row per participant per session. |
| `all_sessions.csv` | The per-session summaries stacked. |
| `all_residents.csv` | Every resident, round and phase. |
| `participants_wide.csv` | **One row per person**, their three sessions side by side: `t1_r2_travel_time_min`, `t3_r1_own_route_spend_share`, and so on. The shape for SPSS or a spreadsheet. |
| `codebook.csv` | Column descriptions. |
| `aggregate_report.txt` | What was read, and what looks wrong. Read it. |

## Read the report

It flags five things that are easy to miss and expensive to discover later:

- **Session kinds**: how many study, pilot, test and unmarked sessions were
  read. If it is not all study, the report says how to filter them out.
- **Incomplete sessions**: no `summary.json`, meaning the session never
  reached its closing survey. Their rounds are still included; deciding whether
  to keep them is a judgement call, so the tool makes it yours.
- **Duplicate participant and treatment**: an ID was used twice. The wide file
  can only keep one of the pair.
- **Half sittings**: someone with T1 but not T2, or the reverse. The two are
  played back to back, so one without the other means the sitting was abandoned.
- **Group sessions without solo data**: someone played T3 but has no T1 or T2
  on file, which almost always means their folders are still on the other
  machine. Until they are copied across, the individual-versus-group comparison
  cannot be made for that person.

## Four things to know before analysing

**`safety` in the tables is the raw 0-100 score, not the stars on screen.** As of
30 Aug 2026 the five-star rating a participant sees measures progress toward what
is reachable on their own route -- `(safety - 50) / (ceiling - 50)`, where the
ceiling is `100 - beta_protected * 50`, so 95 for a cautious rider, 90 average, 70
confident. The number in every CSV, and the number behind the researcher's debug
toggle, is the unchanged raw score. Do not try to recover the stars from a column;
if you need them, apply that formula with the row's own `alpha`.

**Per-seat final figures live in `summary.json` under `players_final`.** The flat
`final_travel_time_min`, `final_safety`, `baseline_travel_time_min` and
`total_travel_time_saved_min` fields beside it describe **seat 1 only**, which in a
group session is one of three people. `players_final` carries all of them, in seat
order. Sessions recorded before 30 Aug 2026 have neither the array nor the other
seats' finals anywhere except their last round row in `rounds.csv`, which has always
been correct.



**`group_id` is blank on individual sessions, and filled in here.** The group is
only asked for in the group treatment, where it ties a separately recorded
discussion to the rounds it covers. An individual session has no group decision
and no recording, so the researcher is not asked. This tool recovers it: any
participant named in a group session has their solo rows filled in with that
group, and those rows are marked `group_id_derived = true`. Still blank after
that means the person never played a group session, so no group exists for them.
The count of rows filled this way is in `aggregate_report.txt`.

**A hidden value is not a missing one.** All three treatments compute the same
city-wide metrics; T1 simply does not show them. Those values are stored anyway,
and `city_metrics_shown` says whether they were on screen. A blank city column
would mean "not calculated" and never occurs. This is what lets you ask whether a
T1 player would have helped the city had they been able to see it.

**`decisions.csv` and `upgrades.csv` are not the same table.** `upgrades.csv` is
what was bought. `decisions.csv` is what was done on the way there: the order
links were chosen in, levels re-picked, and selections withdrawn before
confirming (`selection_order`, `action`, `confirmed`, `changed_or_removed`).
What someone nearly did is evidence about how they decided.


**`_before` is not `_baseline`.** Every metric is recorded three ways.
`_before` is this round's starting value, `_baseline` is the Round 1 value, and
`_delta` is measured against the **baseline**, not against the previous round.
Deltas are signed so positive always means improvement, whichever direction the
underlying metric moves in.

**City and resident columns repeat across a group's rows.** They describe the
session, not the person, so in a three-player session the same city figure
appears on three rows. Summing down those columns counts one city three times.

**In a group session, `participant_id` on a purchase is blank.** Three people
share one screen and one mouse, so the game cannot know whose hand it was. Blank
there means "the group decided", not "missing". Per-person attribution inside a
group session comes from the audio recording, aligned via `audio_manifest.json`.
What *is* per person is `own_route_spend_share`: the share of the group's
spending that landed on that individual's route. It is the column to use when
comparing self-interested against collective allocation, because it holds a real
value for every seat rather than only for the one the budget is recorded
against.

## Comparing the same person alone and in a group

Filter `all_rounds.csv` to one `participant_id` and compare across `treatment`,
or read the person's row in `participants_wide.csv` directly. `sitting_id` groups
the paired T1 and T2 sessions as one visit without a self-join.

Note the two comparisons are not the same kind. **T1 vs T2 is within-subject**
(the same person, back to back, paired on `participant_id`). **T3 changes the
decision unit**: the group decides, while each member still has their own route
and personal outcome, which is why `decisions.csv` is at group grain in T3 while
`rounds.csv` keeps a row per member. Whether T3 is comparable to T1/T2 like for
like is a study-design question, not a schema one.

Two caveats:

- The group treatment assigns every player the **average** personality and skips
  the opening survey (`alpha_source = "default"`). Someone whose individual
  sessions ran at a cautious or confident sensitivity therefore rides a
  different route in the group session, so "their own route" is not the same set
  of links in both. Check `alpha_source` before treating the comparison as clean.
- `treatment_ordinal` is counted per machine, so a T3 session run on a second
  computer reports 1 rather than 3. Join on `treatment`, never on the ordinal.

## Checking which build produced a session

`parameters.json` records the settings and a `network_signature` fingerprint of
the road network. Sessions with different signatures were played on different
networks and are not directly comparable. The network was restructured during
development, which changed route choice substantially.

## What each single upgrade did

Outcomes are recorded once per round, so a round in which someone bought four
lanes leaves one before/after pair and the four purchases are indistinguishable
inside it.

```
python tools/replay_upgrades.py --latest
python tools/replay_upgrades.py --all --kind study
```

This rebuilds the routing model from `network_links.csv` and `parameters.json`,
then replays the session one purchase at a time: it starts from the network as
each round opened and applies that round's purchases in the order they were
chosen, solving every rider's route after each one. The difference between
consecutive steps is that single upgrade's effect, for the participant and for
the city.

It reads only what is already on disk, so it works on every session ever
recorded and cannot affect the game, the schema or determinism. Nothing is
written into the session folder; results go to a `replays/` folder beside the
sessions, one directory per session holding `marginal_effects.csv`, its own
`codebook.csv`, and `replay_report.txt`.

**Read the report first.** The middle of a round is not observed anywhere, so
the only evidence that the steps are right is that both ends of every round land
exactly where the game recorded them. The tool recomputes each round's start and
end state and compares travel time, safety, stress, impedance and the route
itself against `rounds.csv` and `residents.csv`, for all 99 residents as well as
the players, and exits non-zero if any of it disagrees. On the sessions on file
it reproduces roughly 2,400 recorded values per session exactly.

What the file is for: `link_on_own_route` says whether each purchase was on that
rider's own commute at the moment it was made, and the `_marginal` columns say
what it did for them and for the city. Together they put the self-interest
versus collective-good comparison at the resolution of the individual decision
rather than the round. A worked example from a session on file: of four
purchases in one round, three sat on the buyer's own route and moved two
residents between them, while the fourth sat elsewhere, did nothing for the
buyer, and helped nine.

Two things to know. Steps are ordered by `selection_order` in `decisions.csv`,
because marginal effects are not additive and the second protected lane on a
corridor is worth less than the first; a purchase with no matching decision row
keeps its file position at the end. And step 0 is the round's opening state, so
it anchors each round and carries no `_marginal` values.

## Rebuilding the model without the game

`network_links.csv` and `parameters.json` together are enough to reproduce any
route in a session from scratch, so the game's numbers can be audited rather
than taken on trust. Build an undirected graph from `network_links.csv`, weight
each edge by

```
impedance = base_time_min x time_factor[level] x (1 + alpha x beta x base_stress)
```

and run Dijkstra. `time_factor_by_level` and the protected `beta` per
personality are in `parameters.json`; painted `beta` is per link, in
`beta_painted`. At the start of a session every link sits at
`initial_upgrade_level`, and `upgrades.csv` says what changed and when.

Costs check the same way: `length_m` times the per-metre rate for the level,
rounded to the nearest thousand dollars.

## Schema versions

Every row carries `schema_version`. Version 2 (11 August 2026) renamed a number
of columns and changed two encodings, deliberately, while no participant data
existed and nothing could be invalidated:

| Schema 1 | Schema 2 | Why |
| --- | --- | --- |
| `time` | `travel_time_min` | Bare `time` sat next to `timestamp_s` in a 90-column table, and the unit was only in the codebook. |
| `city_avg_time` | `city_avg_travel_time_min` | Same. |
| `credits_spent` / `credits_remaining` | `budget_spent` / `budget_remaining` | The budget is dollars, not coins. "Credits" read as a count of something. |
| `own_route_upgrade_share` | removed | Only ever valid for the seat holding the shared budget, so it reported "nothing spent" for the other players in a group session even in rounds where the group spent most of its money. |

| `group_spend_on_my_route_share` | `own_route_spend_share` | The correct measure becomes the obvious name. |
| `cumulative_own_route_upgrade_share` | `own_route_spend_share_cumulative` | Rebuilt on the correct per-seat measure, as a spend-weighted running mean. |
| `true` / `false` | `1` / `0` | The words load as text and need recoding before they can be averaged. The survey "don't know" flags were already 1/0. |
| `-1` in share columns | blank | `-1` is outside a proportion's real 0..1 range, and no reader rejects it, so it entered means silently. Blank is read as missing everywhere. Use `budget_spent` to tell "spent nothing" from "not applicable". |

**Added under version 2, not a new version:** `session_kind` (24 August 2026) and
`benefit_epsilon_stress` in `parameters.json` (25 August 2026). A new column changes no
existing column's meaning, so folders written before and after them both read as schema 2 and
are distinguished by whether the column is present. A missing `session_kind` means the session
was written before the marker existed, which is what the aggregator reports as `unmarked`.

`events.json` is the source of record and keeps its original field names, so a
few fields there still read `time` and `credits_spent`. The tables are the
analysis surface and are the ones that were renamed.
