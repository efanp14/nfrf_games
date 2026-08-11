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
```

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

It flags four things that are easy to miss and expensive to discover later:

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

`events.json` is the source of record and keeps its original field names, so a
few fields there still read `time` and `credits_spent`. The tables are the
analysis surface and are the ones that were renamed.
