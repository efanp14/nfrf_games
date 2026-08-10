# Data & Game Outputs — Requirements Checklist

Source: **"Road Costs / Data and Game Outputs"** (July 2026, owner + JH/MZ margin comments).
This file tracks every requirement in that document against the current build.

---

## ⚠️ MAJOR OPEN DECISIONS — must be settled before any real session

These are **deliberately not implemented**. They were raised, explicitly deferred, and are
recorded here so they cannot be lost. Each one blocks research output that cannot be
reconstructed after the fact — if sessions are run before these are settled, the resulting data
will be missing the collective-impact measures entirely.

### ~~OPEN 1 — Definition of a "benefiting" resident~~ — ✅ RESOLVED (owner, 4 Aug 2026)
**Benefit is reported as two independent measures, not one weighted score.** The owner's answer:

> *"We should report it as travel time and a star-based safety system (as you have) because
> respondents won't understand 'impedance' from our calculations. For the city, we can have
> simulated values and measure how many people benefit (have shorter travel times and more safe
> travel). We could also show average benefit, so:*
> - *10% of people saw an improvement in their travel time*
> - *The average travel time decrease was 1.3 minutes*
> - *7% of people saw an improvement in comfort/safety"*

So the definition is: **a resident benefits on time if their route travel time fell versus the
Round 1 baseline; a resident benefits on safety if their route safety rose versus the Round 1
baseline.** The two are counted and reported separately. Impedance stays backend-only and is
never named to participants. Reference point is the static Round 1 baseline (OPEN 2). This
unblocks D6–D10.

**Why this is only now measurable.** Before the infrastructure speed bonus went in (3 Aug 2026),
`total_time` summed the immutable `base_time`, so a resident's travel time could change *only* on
a full reroute — a headless test of one protected upgrade moved 7 of 99 residents' stress and
**zero** residents' travel time. The owner's "% saw an improvement in their travel time" line
would have printed 0%. `Dijkstra` now sums `effective_time`, so any resident riding an upgraded
link gains time directly, and the measure returns real values.

⚠️ **Now measured (4 Aug 2026), and the rationale does NOT hold.** The owner's reasoning is that
riders take longer routes to avoid discomfort, so relief "translates into travel time". For the
*player* that mechanism was already known to be largely absent (OPEN 3: fastest route = calmest
route on 4 of 5 pairs). It has now been checked across all 99 residents, by protecting the three
links the most residents ride and comparing every resident's route against the Round 1 baseline:

| | result |
| --- | --- |
| Residents who **changed route at all** | **0 of 99** |
| Benefited on time | 29 (29.3%) |
| Benefited on safety | 29 (29.3%) |
| Benefited on **both** | 29 |
| Time only / safety only | **0 / 0** |
| Mean saving among those 29 | **0.27 min** (~16 seconds) |
| Largest single saving | 0.32 min |

Two consequences the owner needs to know before any figure is quoted to her:

1. **Not one resident rerouted.** The entire time gain is the infrastructure speed bonus
   (`time_factor`, 4% painted / 8% protected) applied to people who were *already* riding those
   links. Nobody was drawn onto a road they previously avoided, which is precisely the emergent
   mechanism the model is built on. This is OPEN 3 confirmed at city scale, not just on the
   player's 5 pairs, and it is the same root cause: stress correlates with length (r = +0.654),
   so there is nothing to detour around.
2. **The two measures are currently the same statistic reported twice.** Because benefit only
   ever arrives by riding an upgraded link, the identical 29 people improve on both, with zero in
   either "only" category. Reporting "29% saw a faster commute" and "29% saw safer travel" as two
   findings therefore overstates what was independently observed. The two measures are still
   correctly implemented and *will* diverge once the network has a real trade-off; they simply
   cannot diverge on this network.

Scale is worth flagging too: the owner's illustrative line was *"the average travel time decrease
was 1.3 minutes"*. The measured figure is **0.27 min**, and the participant-facing sentence
rounds it to "Their average saving was 0.3 min", which reads as trivially small next to a roughly
10 minute commute. The safety measure moves properly by comparison (mean gain 12.4 points, city
safety visibly up by 3.6 points), so the collective story currently rests on safety, not time.

**Recommendation:** fixing OPEN 3 is what makes the time measure meaningful. Until then, quote
the safety figure to participants and treat the time figure as backend data.

**Display:** shown in **T2 and T3 only**, never T1, as additional lines in the existing city
panel (E1).

### ~~OPEN 2 — Reference point for "benefited"~~ — ✅ RESOLVED: STATIC
Settled by the Prospect Theory decision of 3 Aug 2026 (`CLAUDE.md` §3.7), which applies to every
gain and loss measure in the game: time, safety, stress, impedance and the city averages all
compare against the Round 1 baseline. A benefited metric on a previous round reference would be
the only measure in the build using a different reference point, which is not defensible.

So: a resident counts as benefiting when their situation has improved **relative to the untouched
Round 1 network**, and the figure accumulates across rounds. Only the *definition* of benefit
(OPEN 1) remains open. Revisit only if the owner explicitly asks for a per round figure.

### ⚠️ OPEN 3 — The network has no time-vs-stress trade-off *(blocks a headline output)*
**Measured 3 Aug 2026.** The data document requires **"personal travel-time improvement"** in all
three treatments. On the current network that value is structurally near-zero, and no parameter
change can fix it.

For **4 of the 5** home/work pairs, the fastest route **is** the calmest route — an infinitely
stress-averse rider (α = 50) picks the identical path as one who ignores stress entirely
(α = 0). Only pair 7→41 has any tension, worth **1.2 minutes**. Across all 15 personality × pair
combinations, only **2** involve any detour at all.

Root cause: the 4 Aug stress rewrite ties stress to link length
(`stress = 0.55 + 0.30 × normalized_base_time ± noise`), producing a measured correlation of
**r = +0.654** between link time and link stress. Long roads are both slow *and* stressful, so
"avoid stress" and "avoid time" point the same way — leaving nothing to detour around.

This defeats the mechanism the spec is built on (`CLAUDE.md` §3.1): *"lowering β on a link can
make Dijkstra switch the cyclist onto a previously-too-stressful direct road."* That needs the
direct road to be **faster and more stressful**; here shorter roads are *calmer* on average —
the opposite.

⚠️ **Needs the owner specifically.** The correlation is not accidental: the 4 Aug formula was
written to her instruction *"same high stress with some variation, longer roads higher on
average."* Fixing it means revisiting that instruction. The shape required is a subset of
**short, high-stress** arterials plus **longer, low-stress** backstreets — which is also closer
to real LTS, where stress derives from facility type, speed limit and lane count, not length.

*Note: this, not the β double-count, is the true cause of "travel time never moves". Flattening
β changes no routing outcomes at all (measured: 13/15 routes move either way).*

**Confirmed at city scale, 4 Aug 2026.** The finding above came from the player's 5 home/work
pairs. It has now been reproduced across all 99 simulated residents: protecting the three most
heavily ridden links moved **0 of 99 residents onto a different route**. Every measured "time
benefit" was the speed bonus applied to riders already on those links, averaging 0.27 min. This
also collapses the two benefit measures into one (see OPEN 1), so the problem is no longer only
that personal travel time barely moves, it is that the **collective** time story does not exist
either. This raises the priority of OPEN 3 from "blocks a headline output" to "blocks two".

### ~~OPEN 4 — Per-round budget after the cost change~~ — ✅ RESOLVED
Budget re-derived from $2,000,000 to **$1,300,000**, restoring the owner's stated intent of
3–4 typical protected upgrades per round (now 3.57). See A5.

---

**Status key**
- `[x]` **Implemented** — present and matches the document.
- `[~]` **Partial** — something exists but does not fully satisfy the requirement; needs a tweak.
- `[ ]` **Missing** — not implemented at all.
- `[!]` **Conflict** — the build and the document disagree; needs an owner decision before code changes.

**Tally: 63 requirements — 63 implemented · 0 partial · 0 missing.**
*(Every requirement in the source document is now built. One decision remains outstanding with
the owner: **OPEN 3**, the network's missing time-vs-stress trade-off, which is what makes the
collective time measure meaningful.)*
*(Was 51/44 on 3 Aug. The owner's answers of 4 Aug, plus the official survey file, unblocked
D6–D10 and added 12 requirements that this checklist never captured: section **H** participant
identity, section **I** survey content.)*

The three blocks added after 3 Aug are all closed: **D6–D10** the collective-impact measures,
**H1–H5** participant identity, **I1–I7** the surveys and consent removal.

Still needing the owner: **OPEN 3** below. *Conflicts 6, 7 and 8 were all answered and are
closed.*

> Requirements 2.1 / 2.2 / 2.3 in the source document repeat the same backend list three
> times. They are de-duplicated here into sections B–D (common to all treatments) plus
> treatment-specific sections E (T2) and F (T3).

---

## A. Road costs (§1)

| # | Requirement | Status | Notes |
|---|---|---|---|
| A1 | Painted lane unit cost **$60/m** | `[x]` | Adopted. `Player.COST_PER_METRE_PAINTED = 60.0`. |
| A2 | Protected lane unit cost **$200/m** | `[x]` | Adopted. `COST_PER_METRE_PROTECTED = 200.0`. |
| A3 | Three length categories: **150 / 300 / 450 m** | `[x]` | **Deliberately not adopted** — decision was to keep real per-link lengths and take only the unit rates. 0 of 69 links fall in the document's range (actual: 929 m min / 1,821 m median / 5,357 m max), so bucketing would have priced visibly different roads identically. Cost stays continuous. |
| A4 | `Upgrade Cost = Link Length × Unit Cost` | `[x]` | `Player.cost_for_link()`. |
| A5 | Budget scaled so both options stay meaningful | `[x]` | Re-derived to **$1,300,000/round** = 3.57 median protected upgrades, back inside the owner's stated 3–4 intent (it had drifted to 5.5 when rates fell). |

Resulting prices across the 69 real links (verified against every link, not sampled):

| | shortest (929 m) | median (1,821 m) | longest (5,357 m) |
|---|---|---|---|
| Painted | $56,000 | $109,000 | $321,000 |
| Protected | $186,000 | $364,000 | $1,071,000 |

Budget: **$1,300,000/round** — 3.57 median protected upgrades, or 11.9 median painted. Kept
deliberately above the network's most expensive protected upgrade ($1,071,000) so no link is
ever *impossible* to protect in one round, only expensive.

> The document's rates put protected at **3.33×** painted, slightly narrower than the **3.5×**
> the owner requested on 4 Aug 2026. The document's externally-sourced figures were taken as
> authoritative, but the ratio did move — flagging in case that 3.5× was deliberate.

---

## B. Per-participant routing outputs (all treatments)

Computed by `Dijkstra.find_route()` via `GameManager._recalculate_and_end_round()`.

- [x] **B1** — Baseline route between home and work *before any investment* — `route_before` (node IDs) + `route_links_before` (link IDs), captured in `_start_round()` before the network can be mutated.
- [x] **B2** — Updated route after each investment — `results.final_route`, per round.
- [x] **B3** — Links included in each route — `route_links` / `route_links_before`, as **canonical** (direction-independent) link IDs so they join straight onto the upgrade records.
- [x] **B4** — Travel time before and after — `personal_time_before` / `personal_time`.
- [x] **B5** — Total route stress before and after — `personal_stress_before` / `personal_stress` via new `Player.route_stress()` (raw `Σ(β × stress × base_time)`, distinct from the normalised 0–100 safety score).
- [x] **B6** — Total impedance before and after — `personal_impedance_before` / `personal_impedance`. `Dijkstra`'s `total_impedance` was previously computed and discarded by every caller.
- [x] **B7** — Whether the route changes — `route_changed`, from a link-ID comparison.
- [x] **B8** — Whether the upgraded link becomes part of the new route — `on_new_route` per upgrade, plus `upgraded_links_on_new_route` per player. The pre-existing `own_route` flag (pre-purchase route) is retained unchanged — the two answer different questions.
- [x] **B9** — Personal travel-time improvement — `time_delta`.
- [x] **B10** — Personal stress *or* safety improvement — `safety_delta` (existing) + `stress_delta` (new).
- [x] **B11** — Change in total impedance — `impedance_delta`.

> All deltas are signed **positive = improvement**. Time, stress and impedance are better when
> lower, so those read `before − after`; safety is better when higher, so it reads `after − before`.

---

## C. Per-investment decision record (all treatments)

Written by `Player.buy_upgrade()` → `results.upgrades` → `DataLogger`.

- [x] **C1** — Participant ID — `participant_id`, plus per-player IDs in `players[]`.
- [x] **C2** — Treatment and round number.
- [x] **C3** — Selected link or links — `upgrades[].link`.
- [x] **C4** — **Order of link selection** *(JH4: "could be useful to understand the order")* — new append-only `interaction_events` log: `{seq, round, t_s, action, link, level}`, with actions `select` / `change_level` / `unstage` / `stage_removal`. Recorded from the staging layer as the player acts, so re-selections and withdrawals are preserved rather than collapsed into the end state.
- [x] **C5** — Upgrade type (painted / protected) — `upgrades[].level`.
- [x] **C6** — Link length — `length_m` and `base_time_min` per upgrade (and per removal), via new `Player.link_length_m()`.
- [x] **C7** — Upgrade cost — `upgrades[].cost`.
- [x] **C8** — Budget available — `budget_available`, recorded explicitly rather than re-derived (refunds made `spent + remaining` ambiguous).
- [x] **C9** — Total budget spent — `credits_spent` per round; `total_credits_spent` in the session summary.
- [x] **C10** — Remaining budget — `credits_remaining`.

---

## D. Simulated-resident outputs (all treatments)

Currently only *aggregates* exist, in `GameManager._compute_city_metrics()`.

- [x] **D1** — Per-resident routes before and after each investment — `residents_before` / `residents_after` snapshots, written to `residents.json`.
- [x] **D2** — Per-resident travel time before and after — `time` on each snapshot row.
- [x] **D3** — Per-resident route stress before and after — `stress` on each snapshot row (plus `safety` and `impedance`).
- [x] **D4** — Average citywide travel time — `city_avg_time`, now computed in **all three treatments** (*Conflict 2* resolved).
- [x] **D5** — Average citywide **stress** — `city_avg_stress` / `_before` / `_delta`, alongside the existing safety index (which is unchanged).
- [x] **D6** — **Number and percentage of residents benefiting.** `residents_time_improved` / `_pct` and `residents_safety_improved` / `_pct`: two independent measures per OPEN 1, both compared against the Round 1 baseline (`_initial_residents`).
- [x] **D7** — Number and percentage receiving **no** benefit. `residents_time_no_benefit` / `_pct` and the safety equivalent, each the complement of D6. Anyone made *worse* off falls inside that complement but is also broken out separately as `residents_time_worsened` / `residents_safety_worsened`, so "unchanged" and "worse off" stay distinguishable in analysis. Threshold now settled (*Conflict 3*).
- [x] **D8** — Average travel-time improvement **among affected residents.** `residents_time_improvement_mean`, a mean over the benefiting subset only. Verified against an independently recomputed mean, and verified to exceed the whole-city dilution it must not be.
- [x] **D9** — Average stress improvement among affected residents. `residents_safety_improvement_mean`, the same shape as D8 on the safety measure.
- [x] **D10** — **Total benefit generated for residents other than the participant.** `residents_total_time_saved_min` and `residents_total_safety_gained`. Excluding the human player(s) is structural rather than a filter that could rot: the snapshot these sum over holds only simulated residents. Both are net sums across everyone, so anyone made worse off nets off, and the gains-only figure stays recoverable as count × mean.

> Implementation note: residents' routes are currently recomputed from scratch three times
> per round (city metrics, round-end bike animation, and the in-progress NPC heatmap). A
> single cached per-resident before/after snapshot would satisfy D1–D3 *and* remove that
> duplicated work.

---

## E. Treatment 2 — additional requirements (§2.2)

- [x] **E1** — Participants **see citywide outcomes** after each round — *Conflict 4 resolved: T2 and T3 show them.* Three lines in both the live HUD panel and the round summary: city average commute (minutes), city safety (star rating, same scale as personal safety), and network upgraded (%). The round summary additionally shows the change against the round's starting values.
- [x] **E2** — Record **the exact citywide feedback shown** — `city_feedback_shown`, the verbatim lines the participant read (empty in T1). Generated by the same `CityFeedback` helper the UI renders from, so log and screen cannot drift; verified byte-identical.
- [x] **E3** — Mechanics, network, budget, rounds and upgrade options identical to T1 — confirmed identical; only display branches on treatment.

---

## F. Treatment 3 — additional requirements (§2.3)

- [x] **F1** — Shared screen showing all group members' home and work locations — `CityGrid._build()` marks each player's home/work in their own colour.
- [x] **F2** — **Shared** available budget, **fixed** across treatments *(MZ9R8: "Agree with fixed budget")* — one budget of **$1,300,000** (`Player.DEFAULT_CREDITS_PER_ROUND`) regardless of player count; all spending goes through `human_players[0]`.
  *Minor cleanup:* the other `Player` objects still get a `credits_remaining` reset each round that is never spent — dead state that could mislead log analysis.
- [x] **F3** — Personal outcomes for group members — per-player rows in `RoundSummary` / `GameHUD` / `results.players[]`.
- [x] **F4** — Citywide outcomes shown after each round — same implementation as E1; T3 shows the identical three lines.
- [x] **F5** — Need not display every route simultaneously — currently all routes *are* drawn (striped); the in-progress NPC heatmap toggle gives the cleaner alternative the document allows.
- [x] **F6** — **Group ID** — `group_id`, generated per session in `DataLogger` and stamped on **every** entry (rounds, consent, pre/post-survey, final, session summary).
- [x] **F7** — Participant IDs within the group — `participant_ids[]`, index-aligned with `players[]`.
- [x] **F8** — Whether a selection was changed or removed before confirmation — covered by the C4 event log (`change_level` / `unstage`). Confirmed removals of already-built upgrades are additionally recorded in a new per-round `removals` array — previously they went through `downgrade_link()` and left **no trace in the log at all**.
- [x] **F9** — **Total group decision time** — `decision_time_s` per round (round start → confirm), plus `total_decision_time_s` in the session summary.
- [x] **F10** — The final shared decision — `results.upgrades`.
- [x] **F11** — **Audio recording / transcript linked by group ID + session ID + round number** — new per-session `audio_manifest.json` gives absolute UTC start/confirm times per round, plus offsets in seconds from session start, alongside `group_id` / `session_id` / `treatment` / `participant_ids`. A recording made on a separate device can be cut into per-round segments and each segment joined to that round's decisions in `events.json`.
  The game deliberately does **not** record audio — `CLAUDE.md` §6 keeps the recording and diarization pipeline external. If a capture hook inside the game is ever wanted, that is a separate decision and a separate build.

---

## G. Cross-cutting

- [x] **G1** — *"The same core decision and outcome variables should be calculated in all three treatments, even when some results are hidden from participants."*
  **Satisfied.** City metrics and the per-resident snapshot are now computed and logged unconditionally; the sole remaining treatment branch is the `city_metrics_updated` display signal. Verified: T1 logs full city data while emitting nothing to the UI.

---

## H. Participant identity and cross-treatment linking

*Added 4 Aug 2026.* The source document only implies this, in the margin exchange on p.6
(**JH10:** *"To link between treatments?"* → **MZ11R10:** *"Exactly."*). It was missing from this
checklist entirely until the owner's 4 Aug answers made the requirement explicit.

**Owner's decision (Q2):** *"Option B is what we had in mind. Each person receives an id (e.g.,
participant id 1, 2, and 3 are in group 1; 4, 5, 6 are in group 2, etc.) and plays individually on
separate computers. This saves us some time because we don't have to wait for players to play
sequentially on the same computer. The other reason is that if people are playing in turn and see
the process, it may influence their individual choices."*

- [x] **H1** — **Participant ID entered at session start.** A free-text field per player on the main menu, rebuilt when the player count changes. Start is blocked on a blank ID, a duplicate, or any character outside letters/digits/hyphen/underscore — IDs become filenames in the participant store, so a slash or colon would either fail to write or write somewhere unintended, and a duplicate would merge two people's records irrecoverably. Was: generated as `session_<timestamp>` + player index, which cannot identify a person across sessions.
- [x] **H2** — **Group ID recorded per session.** Its own field on the menu, **auto-filled** from the owner's sequential scheme while the IDs are plain numbers (1-3 → `g001`, 4-6 → `g002`, via `ResearchConfig.suggested_group_id()`), and editable at any point. `GROUP_SIZE` is a named constant, not a literal, because the T3 player count is separately adjustable and the two can disagree.
  *Why not derived outright:* IDs are free text, so arithmetic derivation cannot work in general. When the IDs are not numeric the suggestion is deliberately **blank** rather than a guess, and Start is blocked until a group is typed — recording an invented group number as though it were derived would be worse than admitting it is unknown. A manually typed group is never overwritten by later edits to the IDs.
- [x] **H3** — **Entered IDs replace the generated ones.** `DataLogger.set_participant_identity()` takes the entered IDs and group; `participant_id` and `treatment_ordinal` now appear on round entries, survey entries and the session summary, and flow into `residents.json` / `audio_manifest.json` through the identity they already stamped. The timestamp `session_id` remains as the *run* identifier and still names the output folder. The generated group form survives as a fallback for a blank entry, so the identity can never be empty and the output path can never collapse.
- [x] **H4** — **One survey per participant, not per treatment** *(owner Q3)* — **the T1 → T2 half**. `ParticipantStore` keeps each participant's responses and α under `user://participants/<id>.json`; `main.gd._advance_survey_queue()` asks only those with no record. The rule is *"do we already know this participant"*, deliberately **not** *"is this treatment 1"* — so a returning participant on their own machine is skipped, while the shared group-session machine, which has never seen them, still asks. **Superseded for the group treatment by the 5 Aug decision** (*Conflict 6*): T3 now skips the survey entirely and assigns the average personality, so this queue governs T1 and T2 only.
- [x] **H5** — **Fixed treatment order, no counterbalancing** *(owner Q4)* — `treatment_ordinal` (1 = this person's first treatment) is derived from the store and logged on every round and survey entry. The treatment is recorded as played only once the game actually starts, so abandoning at the menu does not consume a slot. **Do not add counterbalancing:** the order is fixed by design, because the study measures the sequential increase in information.

---

## I. Survey content (official wording)

*Added 4 Aug 2026.* Source: **`NFRF-Transportation_survey_questions`**, supplied by the owner as
the authoritative wording. ⚠️ **The built surveys match neither this file nor `CLAUDE.md` §9.**
The P0 roadmap line *"VERIFY pre/post surveys match §9 exactly"* was never actually true.

| | Official file | Built (`scripts/ui/PreSurvey.gd`, `PostSurvey.gd`) |
|---|---|---|
| Pre-survey | 11 questions (5 demographic, 2 cycling behaviour, 4 attitude) | **4 questions**, all invented wording, **no demographics at all** |
| Post-survey | 7 questions | **13 questions** in 4 invented sections |
| Scale | 6 options incl. *"Don't know / Not applicable"*, listed **agree first** | 5 numbered buttons, ascending |

- [x] **I1** — Pre-survey demographics **Q1–Q5**, all five now built: age (14 brackets), gender (with the free-text *"I identify as"* revealed only when that option is chosen), employment status (7 options), work/school arrangement, driver's licence. Rendered as dropdowns whose first entry is a *"Select…"* prompt, so no real option can stand as an unnoticed default. Previously none of these existed.
- [x] **I2** — Pre-survey cycling behaviour **Q6–Q7**, verbatim, as fixed-choice questions.
- [x] **I3** — Pre-survey attitude items **Q8–Q11**, verbatim, including the **"saved 5 minutes"** trade-off clause that the previous invented item had dropped entirely.
- [x] **I4** — **Six-point scale incl. "Don't know / Not applicable", presented agree-first**, in `scripts/ui/SurveyScale.gd` and shared by both surveys. Rendered as a labelled matrix: the six full option wordings appear as column headers and each question gets radio buttons beneath them, so participants read the actual response wording rather than decoding bare numbers as they did before.
- [x] **I5** — **α = mean(Q8..Q11)**, in `SurveyQuestions.alpha_mean()`, on an explicit map where agreement always scores 5 and disagreement 1 **regardless of on-screen order**, so reordering the buttons can never silently reverse the scoring. All three consequences handled: **(a)** the reverse-scoring of the old `q2` is gone, since no official item is reverse-worded; **(b)** *"Don't know"* scores as the neutral middle and is logged as `dk` rather than as a number; **(c)** the `get(key, 3)` default is gone, replaced by skipping absent answers, which cannot happen anyway since the survey will not submit until every question is answered.
- [x] **I6** — Post-survey **Q1–Q7**, verbatim. Q5–Q7 are shown only in T3, so T1 and T2 participants are asked 4 items and are never questioned about a discussion they did not have.
- [x] **I7** — **Consent screen removed from the game** *(owner Q5: "The consent will be a separate process"; confirmed again 5 Aug 2026: it will be signed in person)*. `ConsentScreen.tscn` and `.gd` are deleted and the node is out of `Main.tscn`; a session now opens straight onto the first survey. The **CONSENT log entry is kept**, not dropped: removing it would break the schema, and a missing entry is ambiguous because it cannot be distinguished from a session where consent was never recorded at all. It now carries `consent_process: "external"` with `timestamp_s` present but null, since there is no in-game moment to timestamp. The session summary keeps `consent_given_at_s` (now null) and gains `consent_process`, so a reader that already looked for the old field still finds it.

---

## Conflicts requiring a decision

### ~~Conflict 1 — Link lengths / unit costs~~ — RESOLVED
**Decision: keep real per-link lengths, adopt only the $60/$200 unit rates.** Implemented and
verified. The document's three length categories are not used. Consequence for the budget is
still open — see ⚠️ OPEN 3.

<details>
<summary>Original analysis (kept for the record)</summary>

#### Conflict 1 — Link lengths: 150/300/450 m vs. 929–5,357 m
The document prices three representative link lengths off Calgary Complete Streets guidance.
The built network's links are **4–12× longer than the document's "long" category**, because
`base_time` is derived from on-screen pixel distance and then converted at 357 m/min.
**Zero of 69 links** fall inside 150–450 m.

Options:
1. **Re-scale the metres-per-minute conversion** so real link lengths land in the 150–450 m
   band. Cheapest change (one constant); costs then match the document's table almost exactly.
   Side effect: the network's stated real-world scale shrinks to a ~2 km-wide city.
2. **Bucket each link into short/medium/long** and charge the document's flat $9k–$90k prices.
   Matches the document literally and is easy to defend in writing, but two visibly different
   roads can cost the same.
3. **Keep continuous lengths, adopt only the $60/$200 rates.** Costs then run $56k–$1.07M per
   link — internally consistent, but no longer reconcilable with the document's table.

Whatever is chosen, **the per-round budget must be re-derived at the same time** (A5).

*(Option 3 was chosen.)*
</details>

### ~~Conflict 2 — City metrics are not computed in T1~~ — RESOLVED
Resolved in favour of the document, which states this as its own main requirement and which
agrees with the project's display-only guardrail. City metrics and per-resident snapshots are
now computed in every treatment; only the display signal is gated. No owner decision was needed
— the two sources agreed.

### ~~Conflict 3 — "Benefiting" is undefined~~ — ✅ RESOLVED (owner, 4 Aug 2026)
Defined as two independent measures, time and safety, each against the Round 1 baseline. See
OPEN 1 at the top. **The surviving sub-question, the "no change" threshold, is now settled**
(4 Aug 2026, not owner-blocking): a tolerance band of **0.01 min** and **0.01 safety points**,
held in `GameManager.BENEFIT_EPSILON_TIME` / `BENEFIT_EPSILON_SAFETY`. Movement below that is
floating-point dust from summing many link values, and exact equality would have reported it as
benefit. The band sits well below the smallest real effect observed (individual savings measured
so far run from roughly 0.1 to 0.32 min), so it discards noise without discarding signal.

### ~~Conflict 6 — T3 has no access to its participants' α~~ — ✅ RESOLVED (owner, 5 Aug 2026)
**Decision: the group treatment assigns every player the AVERAGE personality and does not run the
opening survey at all.** The owner's reason was the friction of surveying everyone again. Built and
verified; `ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA` is the single flag that governs it,
and flipping it to `false` restores surveying with no other change.

Applied to **every** player in the session, not only those with no stored record, so the whole
group runs at one sensitivity rather than one member differing because they happened to play an
earlier treatment on that particular machine.

⚠️ **This is a sanctioned exception to guardrail 1 ("treatment is display only").** It is the one
place a treatment changes a routing input rather than only what is displayed. Do not remove the
branch as a guardrail violation, and do not treat it as licence for other treatment branches.

⚠️ **Known analytical cost, raised twice before the decision and accepted.** A person whose
individual sessions ran at cautious (α 3.0) or confident (α 0.4) sensitivity experiences their own
commute differently in the group session, so a change in how they invest between their individual
and group sessions has more than one possible explanation. That sits on the study's primary
comparison. Mitigation: every affected row carries `alpha_source = "default"`, so defaulted
participants are identifiable and can be separated in analysis. A defaulted session deliberately
writes **no** participant record, so it can never be mistaken for a real survey later.

<details>
<summary>Original analysis (kept for the record)</summary>

#### Conflict 6 — T3 has no access to its participants' α
"One survey per participant" (owner Q3) plus "separate computers" (owner Q2) means the machine
running T3 has never seen the three participants' pre-surveys, yet α determines each member's
routing and personal outcomes. α enters the game through exactly one path and no other:
`scenes/main.gd:84` is the only place a value is produced, straight from the survey that just ran,
and `scenes/main.gd:106` hands the array to `GameManager.start_game()`. There is no load, lookup
or manual entry. T3 currently works *only* because `scenes/main.gd:92` re-asks once per player.

**Status: parked at the owner's request.** Her provisional answer is *"either we will not ask them
to do the survey or we will make them do it again"*, pending a further email. Both of those are
buildable, but they are different builds, so **do not pick one**. Until she answers, T3 keeps its
current behaviour of asking each player on the shared machine.

Note the "don't ask again" branch is the harder one: it still needs a way to *get* the three α
values onto that machine, so it implies the stored-per-participant-ID mechanism whether or not
that is what she pictures.
</details>

### ~~Conflict 7 — "Don't know / Not applicable" has no numeric value~~ — ✅ RESOLVED (owner, 4 Aug 2026)
**Decision: a "Don't know / Not applicable" response scores as the neutral middle of the scale**,
identical to "Neither agree nor disagree", **and is recorded in the log as `dk` rather than as a
number** so analysis can distinguish a genuine neutral from a non-answer.

Consequence worth knowing: a participant who answers DK to all four of Q8–Q11 gets a mean of
exactly 3.0, which falls inside the 2.5–3.5 band in
`PersonalityConfig.alpha_for_survey_mean()` and yields the **Average** personality (α = 1.5).
That is the same outcome an explicit all-DK fallback would have produced, so the simpler per-
response rule covers the edge case without a special branch, *and* it also handles a participant
who skips only one or two items, which a whole-survey fallback would not.

### ~~Conflict 8 — The survey file describes a multimodal game~~ — DISMISSED (owner, 4 Aug 2026)
The **GAME ELEMENTS** section of `NFRF-Transportation_survey_questions` describes city averages
*"by mode (i.e., walking/biking, private vehicle, and public transport)"* on *"a simple gridded
road network"*, neither of which matches current scope. **The owner confirmed this section is
commentary around the survey questions, not a specification of the game.** Not a conflict; do not
raise again. The file's *survey wording* remains authoritative (section I); its game description
does not.

### ~~Conflict 4 — Showing citywide numbers to participants~~ — RESOLVED
**Decision (3 Aug 2026): T2 and T3 participants see the city-wide stats.** This overrides the
6 July "numbers only for time and money" rule *for city metrics specifically* — personal safety
remains a star rating, and city safety uses that same star scale for consistency rather than a
bare number. Implemented in the live HUD and the round summary; the exact text shown is logged.

### ~~Conflict 5 — Round count and budget scale are unstated~~ — RESOLVED
**Session length confirmed at 3 rounds** (owner, 3 Aug 2026: "6 is too much"). Both `CLAUDE.md`
files said 6 and have been corrected, along with their stale "5 coins per round" figure — the
budget is a dollar amount now ($1,300,000/round, see A5).

### Non-conflict, noted
The document derives costs from **Calgary** guidance while the network deliberately uses a
**fictional city with no real place names**. These do not clash — the Calgary figures are a
costing basis, not a label shown to participants.

---

## Suggested sequencing

**Phase 1 — no decisions needed (pure additions, all low risk) — ✅ COMPLETE**
- [x] B6 + B11 — capture `total_impedance` before/after and its delta.
- [x] B5 + B10 — capture raw route stress before/after and its delta.
- [x] B1 + B3 + B7 — log the before-route as link IDs; derive a `route_changed` flag.
- [x] B8 — add `on_new_route` per upgrade, alongside the existing `own_route`.
- [x] C6 + C8 — add `length_m`, `base_time_min`, `budget_available` per upgrade record.
- [x] C4 + F8 — append-only interaction event log (sequence, timestamp, action, link, level).
- [x] F9 — round decision timer (round start → confirm).
- [x] F6 — group ID on the session and every round entry.
- [x] D5 — average citywide stress alongside average citywide safety.

**Phase 2 — ✅ COMPLETE**
- [x] G1 + D4 — compute city metrics in every treatment; keep display gated.
- [x] D1–D3 — cached per-resident before/after route, time and stress snapshot.

**Phase 3 — ✅ COMPLETE (4 Aug 2026)**
- [x] D6–D10 — benefiting counts, percentages, average improvements, total external benefit.
  Both blocking decisions were answered first: two independent measures (OPEN 1), static Round 1
  reference (OPEN 2). Built as arithmetic over the existing per-resident snapshot in
  `residents.json`, plus the benefit sentences in the T2/T3 city panel. Verified by a headless
  probe (18 checks, all passing) covering: a do-nothing round benefiting nobody, counts and
  percentages agreeing, improved plus no_benefit summing to the total, the mean being taken over
  the benefiting subset rather than the whole city, gains persisting through a later do-nothing
  round (which is what makes the reference static rather than per round), and the logged
  `city_feedback_shown` text being byte-identical to what the summary renders.
  ⚠️ The measures are correct, but on the current network they cannot diverge from each other.
  See the measurement recorded under OPEN 1 before quoting any time figure to the owner.

**Phase 7 — participant identity (H1–H5) — ✅ COMPLETE (5 Aug 2026)**
- [x] H1 + H3 — participant ID entry; entered IDs carried through every output file.
- [x] H2 — group derived from participant ID, group size in config.
- [x] H4 — pre-survey stored per participant and skipped on their second treatment (T1 → T2 half; *Conflict 6* governs the group-session machine only).
- [x] H5 — record the treatment ordinal; no counterbalancing.

**Phase 8 — surveys and consent (I1–I7) — ✅ COMPLETE (5 Aug 2026)**
- [x] I1–I3 — pre-survey rebuilt to the official 11 questions.
- [x] I4 — shared six-point scale incl. "Don't know / Not applicable", agree-first.
- [x] I5 — α rescored: mean(Q8..Q11), no reverse-scored item, DK rule (*Conflict 7*).
- [x] I6 — post-survey rebuilt to the official 7 questions.
- [x] I7 — consent screen removed from the flow; consent is collected in person.

> ⚠️ **I5 is research-critical and easy to get quietly wrong.** α feeds routing for every rider,
> so a scoring change silently alters every route and every metric in the study. Rescoring must
> be verified against worked examples at both ends of the scale, not assumed.

**Phase 4 — ✅ COMPLETE**
- [x] E1 + F4 — citywide feedback display in T2/T3.
- [x] E2 — log the exact feedback shown.

**Phase 5 — ✅ COMPLETE**
- [x] A1, A2 — adopt the document's $60/$200 unit rates.
- [x] A3 — decision recorded: real per-link lengths kept, categories not adopted.
- [x] A5 — per-round budget re-derived to $1,300,000.

**Phase 6 — ✅ COMPLETE**
- [x] F11 — round-boundary manifest for transcript alignment (`audio_manifest.json`).

---

## Progress log

### Owner's answers received — 4 Aug 2026
Five questions answered. Net effect: **two open decisions closed, 12 requirements added.**

| Q | Answer | Effect |
|---|---|---|
| 1. Benefit definition | Two independent measures, time and safety, reported separately with averages. Impedance never shown to participants. | **OPEN 1 + Conflict 3 resolved.** D6–D10 unblocked. |
| 2. Treatment linking | **Option B.** Participant IDs, groups of three, played on separate computers. | **New section H** (5 requirements). |
| 3. Surveys | One survey per participant. Official wording supplied. | **New section I** (7 requirements); **Conflicts 6 + 7 raised.** |
| 4. Order | Fixed T1 → T2 → T3, deliberately **not** counterbalanced, because the study measures the sequential increase in information. | H5, recording only. |
| 5. Consent | Handled externally, on paper or by e-signature. | I7, remove the screen. |

**The survey file is the significant finding.** The built surveys match neither it nor
`CLAUDE.md` §9: the pre-survey has 4 invented questions against the official 11 and captures **no
demographics at all**, and the post-survey has 13 invented questions against the official 7. The
scale also changed to six points with a "Don't know" option, which α has no rule for. This means
the P0 roadmap line *"VERIFY pre/post surveys match §9 exactly"* had been standing as verified
without ever being true.

Also noted: the survey file's GAME ELEMENTS section describes a **multimodal** game (private
vehicle and public transport) on a **gridded** network. Both contradict current scope and are not
being built (*Conflict 8*), but the owner should know, since that file is circulating as
authoritative.

### Phase 1 — complete
Closed **B1, B3, B5, B6, B7, B8, B10, B11, C4, C6, C8, D5, F6, F8, F9** (12 requirements moved
from missing/partial to implemented; F11 advanced but still open).

Touched: `scripts/Player.gd`, `scripts/GameManager.gd`, `scripts/DataLogger.gd`, `scenes/main.gd`.
No changes to routing, costs, metric maths, or determinism. All schema changes are **additive** —
no existing log field was renamed or removed. Verified by a headless harness that drove a full
two-round session and asserted 33 conditions on the resulting log (all passed, harness then removed).

**Two behaviour changes worth knowing about, beyond pure additions:**

1. **`city_avg_time_delta` sign was corrected.** It previously read `after − before`, so a city
   that got *faster* logged a *negative* delta — the opposite of every other delta in the schema
   and of the "positive = improvement" rule the project spec states. It now reads
   `before − after`. This is a fix, but it does change the meaning of an existing field: any
   analysis written against pre-Phase-1 logs must flip the sign.
2. **Confirmed removals are now logged.** Taking an upgrade back off the network previously
   left no record whatsoever. They now appear in a per-round `removals` array (deliberately
   separate from `upgrades`, so nothing derived from `upgrades` shifts).

Also fixed incidentally: `Player.route_safety()` and the new `route_stress()` were sharing a
copy-pasted loop; both now route through one `_stress_sum()` helper, and the metres-per-link
conversion inside `cost_for_link()` was extracted to `Player.link_length_m()` so length has a
single definition.

### Phase 2 — complete
Closed **D1, D2, D3, D4, G1** and resolved *Conflict 2*.

City metrics and a new per-resident snapshot are now computed at both round boundaries in
**every** treatment. The only surviving treatment branch is the `city_metrics_updated` display
signal, so T1 now produces a complete city-level dataset while showing the participant nothing —
which is what both the requirements document and the display-only guardrail ask for.

New output file: **`residents.json`** per session, holding each resident's before/after route
(as link IDs), travel time, stress, safety and impedance, one block per round. Kept separate
from `events.json` so ~99 residents × 2 snapshots × N rounds don't bury the participant rows.

Efficiency side effect: residents' routes were previously re-solved once per metric. They are
now solved once per round boundary and every average is derived from that one snapshot —
verified by recomputing `city_avg_time` from the logged rows and matching it exactly.

Verified by a second headless harness (T1 and T2 sessions, 22 assertions, all passed): T1 logs
every city field, emits no display signal, and a single protected upgrade measurably moved
7 of 99 residents.

### Phase 5 (cost model) — complete except the budget
Closed **A1, A2, A3** and resolved *Conflict 1*: real per-link lengths kept, only the document's
$60/$200 unit rates adopted. Verified against all 69 links (rate holds exactly on every one,
not just sampled), and a full round still spends and balances correctly.

Prices fell across the board — median protected upgrade $510,000 → $364,000 — so the budget was
re-derived from **$2,000,000 to $1,300,000** to hold the owner's stated 3–4 typical protected
upgrades per round (it had drifted to 5.5 when prices dropped while the budget stayed put).

The budget is sized against the **median** protected upgrade rather than set as a flat figure,
so it can be re-derived automatically if unit rates move again. It is deliberately kept above
the single most expensive protected upgrade ($1,071,000) so no link is ever unbuyable in one
round — only expensive.

Verified: 3.57 median protected / 11.93 median painted upgrades per round; the costliest
still-unimproved link buys successfully; and an attempt to protect the *entire* network in one
round spent $1,229,000 of $1,300,000 and correctly refused the remaining 121 purchases without
the budget ever going negative.

*Incidental finding:* the network ships with several links pre-upgraded, including the single
most expensive one (1↔2, 5,357 m, protected). Worth knowing when reasoning about what a player
can actually buy — the priciest link on the map is already built.

### Phase 4 (city-wide feedback) — complete
Closed **E1, E2, F4** and resolved *Conflict 4*: **T2 and T3 participants now see the city-wide
stats.** Three lines, in both the live HUD panel and the round summary:

```
City average commute:   10.2 min
City safety:            ★★★☆☆   (▲ 0.6 pts better)
Network upgraded:       13%     (▲ 1.4 pts better)
```

Change indicators appear only in the round summary (where before/after belongs) and only when a
metric actually moved. Travel time stays a raw number per the existing convention; city safety
reuses the personal-safety star scale so the two read together rather than mixing a number
against stars.

New file `scripts/ui/CityFeedback.gd` is the single definition of this text. The HUD, the round
summary and the logger all render from it, which is what makes E2 ("record the **exact**
citywide feedback shown") trustworthy — verified byte-identical between the logged
`city_feedback_shown` and what the round summary renders. T1 logs an empty list and shows
nothing, while still computing every underlying metric.

Note this partially overrides the 6 July "raw numbers only for time and money" rule: it now
applies to *personal* metrics, while city metrics are shown outright in T2/T3. Personal safety
is still stars-only.

### Prospect Theory reference point — committed to STATIC (3 Aug 2026)
Resolves `CLAUDE.md` §14 Q3, open since before this document arrived. The build previously used
a **dynamic** reference: `Player.baseline_time` was overwritten at the end of every round, so
each round compared only to the one before. That roll-forward is removed.

Every metric now records three values per round — `*_before` (this round's start, preserving the
before/after pairs the data spec requires), `*_baseline` (the Round-1 value), and `*_delta`
(gain/loss vs the baseline). Baselines are captured once at game start for time, safety, stress
and impedance, and for the city-wide averages.

Participant wording was updated to match ("faster than your original commute", not "than last
round"), and the city feedback panel now compares against Round 1 too — so what a participant
reads is the same framing the log records.

Verified by investing in Round 1 and then spending nothing in Rounds 2 and 3: the safety gain
holds at **+18.49 across all three rounds**, where a dynamic reference would have collapsed it
to zero. Baselines confirmed constant, deltas confirmed to equal `now vs baseline` rather than
`now vs before`, and the per-round before/after pairs confirmed unbroken.

> ⚠️ **Observation, not a defect — but it needs the owner's attention.** In that same test,
> upgrading three protected links along the player's own route moved safety, stress and
> impedance, but **`time_delta` stayed at 0.000 in every round**. The player's route was already
> optimal, so it never switched — and since `base_time` is immutable, travel time can only change
> on a reroute. The data spec asks for "personal travel-time improvement" as a headline output,
> and for many participants it will simply be zero. This is the routing-calibration issue
> (`CLAUDE.md` §14) showing up in the data, and it compounds with the move from 6 rounds to 3.

### Research-neutrality fix (3 Aug 2026)
Removed the end screen's strategy label, which closed every session by telling the player they
were a **"Civic Champion"**, **"Collective Builder"**, **"Personal Optimizer"** or
**"Mixed Planner"** based on how much of the network they had upgraded.

That screen appears immediately before the post-survey, whose items ask about distributional
fairness, whether the player prioritised their own route, and willingness to accept a worse
personal commute for citywide benefit. Labelling — and implicitly praising — a strategy right
before asking those questions risks steering the responses. Self- versus collective-oriented
investment is the study's dependent variable, so the game must not evaluate it back to the
participant. A comment in `EndScreen.gd` records this so it isn't reintroduced.

Also confirmed: **audio capture stays out of the game entirely** — the manifest (F11) plus an
externally recorded file is the whole approach.

### Phase 6 (audio linkage) — complete
Closed **F11**. New per-session `audio_manifest.json`:

```json
{
  "session_id": "session_1785813675",
  "group_id":   "group_1785813675",
  "treatment":  2,
  "participant_ids": ["p1", "p2", "p3"],
  "session_started_utc": "2026-08-04T03:21:14Z",
  "rounds": [
    { "round": 1, "started_utc": "2026-08-04T03:21:14Z",
      "confirmed_utc": "2026-08-04T03:21:15Z",
      "started_offset_s": 0.0, "confirmed_offset_s": 1.10,
      "decision_time_s": 1.10 }
  ],
  "alignment_note": "..."
}
```

Offsets are anchored to the **earliest** known moment in the session rather than blindly to the
logger's start time, so they can never come out negative. The file carries a self-documenting
`alignment_note` stating the one thing it cannot know — when the external recorder was started —
so that belongs in the session protocol.

**Two robustness bugs were found and fixed while verifying this**, both in `DataLogger`:
1. **Session identity could be empty**, producing the path `research_sessions//` — every session
   would then silently overwrite the same files. Identity is now assigned lazily on first use
   (`_ensure_session_identity()`) as well as in `_ready()`, so the folder can never collapse.
   This was observed for real: a probe run wrote loose `events.json` / `residents.json` /
   `audio_manifest.json` into the research root instead of a session folder.
2. **Round offsets could be negative** if identity was assigned after round 1 began — fixed by
   the earliest-moment anchor above.

### Phase 3 (resident benefit measures, D6–D10) — complete, 4 Aug 2026

`GameManager._compute_benefit_metrics()` compares the round's resident snapshot against
`_initial_residents`, the Round 1 baseline, and returns the D6–D10 fields. They are merged into
both the round results and the city metrics, so they reach `events.json` and the T2/T3 city panel
through the paths that already existed rather than through a new one. `CityFeedback.benefit_lines()`
renders the participant-facing sentences, keeping the guarantee that the logged feedback text and
the displayed text come from a single source and cannot drift.

Design points worth not relitigating:
- Time and safety are counted **separately and never combined** into a weighted score, per the
  owner's answer. A resident can benefit on one, both, or neither.
- "No benefit" is the complement of "improved", so it includes residents made worse off.
  `*_worsened` is reported alongside it so analysis can still separate "unchanged" from "worse".
- Averages cover the **benefiting subset only**. Dividing by the whole city would pull the figure
  toward zero and would not answer the owner's "the average decrease was X minutes" question.
- The totals exclude the human player(s) structurally: the array they sum over contains only
  simulated residents, so there is no filter to forget to update.
- Impedance takes no part in any of it. It is a routing quantity that means nothing to a
  participant, so it stays backend-only.

**Two defects were found and fixed in the verification harness while confirming this**, both
worth remembering because neither is specific to this feature:
1. **Autoloads are not reachable from `SceneTree._initialize()`.** `/root/GameManager` resolves to
   nothing that early because the tree is not yet active, and since the failure happened before
   any `quit()`, the run span forever rather than erroring out. Headless probes must do their work
   on the first `_process()` frame instead.
2. **GDScript lambdas capture local variables by value.** A signal handler written as
   `signal.connect(func(_r, res): captured = res)` where `captured` is a local writes only to the
   closure's private copy, and the outer variable stays empty. The capture target has to be a
   member variable, or a named method. This one is silent: no error, just empty data.

The harness itself was removed after passing, in line with how earlier probes in this project were
handled. The numbers it produced are recorded under OPEN 1.

### Surveys rebuilt to the official wording (I1–I6) — complete, 5 Aug 2026

Both surveys now carry the wording from `NFRF-Transportation_survey_questions`, replacing the
invented items that had been shipping. Content lives in `scripts/ui/SurveyQuestions.gd` and the
response scale in `scripts/ui/SurveyScale.gd`; the two survey scripts only render and collect, so
neither can drift from the official text or from each other.

What changed, and why each mattered:

| Before | Now |
| --- | --- |
| 4 invented attitude questions, no demographics at all | The official 11: five demographic, two on cycling behaviour, four attitude items |
| One item reverse-scored (`q2`) | No reverse scoring, because no official item is reverse-worded |
| "I am willing to use busy roads even without a bike lane" | "I would cycle on a busy road with no bike lane **if it saved 5 minutes**" |
| 13 invented closing questions in four construct blocks | The official 7, with the three group items shown only in T3 |
| Bare numeric buttons 1 to 5, no anchor labels shown | Six labelled points, agree-first, incl. "Don't know / Not applicable" |
| `_responses.get(key, 3)` absorbing a missing answer as neutral | Absent answers skipped; submission blocked until every question is answered |

The single most consequential fix is the missing "if it saved 5 minutes" clause. Without it the
item measured general willingness rather than a risk-versus-benefit trade-off, and it feeds α,
which sets stress sensitivity and therefore drives every route the game computes. Personality was
being assigned from a different instrument than the study documents.

**This breaks the survey response schema, deliberately.** Response keys move from `q1`–`q4` and
`op_*` / `df_*` / `cw_*` / `dqi_*` to the official `q1`–`q11` and `q1`–`q7`. Guardrail 6 asks for a
stable schema, but the old keys recorded answers to questions that are not in the study, so there
is no valid collected data for the change to invalidate. Preserving those keys would have meant
preserving the wrong instrument. Two fields were **added** rather than changed, so analysis can
reproduce the personality assignment without re-implementing the scale: `alpha_mean` (the mean
behind α) and `personality` (the label, derived from α so the two cannot disagree).

Verified by a headless probe, 37 checks passing, covering the question counts and verbatim
wording of both surveys, the scale's ordering and DK handling, α at both extremes and with DK
answers, the T1-versus-T3 gate on the group items, and the logging path end to end including that
DK is written as `dk` and demographics survive into the log. Harness removed after passing.

**Note on running headless probes here:** new `class_name` scripts are invisible until Godot's
global class cache is refreshed, so a probe referencing them fails to parse with "Identifier not
declared in the current scope" even though the files are correct. A `--import` pass registers
them. Match the binary to the version the project's editor is using rather than whichever Godot
is nearest to hand.

**I7 (removing the consent screen) is still open** and was not part of this work. `ConsentScreen`
is still in the flow at `scenes/main.gd:13`.

### Consent screen removed (I7) — complete, 5 Aug 2026

Confirmed by the owner on 5 Aug: consent will be signed in person, so there is nothing for the
game to collect. `ConsentScreen.tscn` and `scripts/ui/ConsentScreen.gd` are deleted, the node is
out of `Main.tscn`, and `scenes/main.gd` no longer holds the reference, the two signal
connections, the accept and decline handlers, or the deferred timestamp. Starting a session now
goes straight from the menu to the first survey.

**The log entry was kept rather than deleted**, which is the one judgement call here. Dropping it
would break the schema, but the stronger reason is that a missing entry is ambiguous: it reads
identically to a session where consent was never recorded at all. The entry now says which
process was used:

```json
{ "round": "CONSENT", "consent_process": "external", "timestamp_s": null, ... }
```

`timestamp_s` stays present and null because there is no in-game moment to stamp. The session
summary keeps `consent_given_at_s` (null from now on) and gains `consent_process` alongside it,
so anything already reading the old field still finds it rather than erroring on its absence.

Verified by a headless probe, 9 checks: `Main.tscn` still loads and instantiates with no dangling
node, no `ConsentScreen` child remains while the menu, survey and orientation screens do, the
CONSENT entry is still written and marked external, and the summary carries both fields. Harness
removed after passing.

One consequence worth noting for the session protocol: the game no longer has any record of *when*
consent was given, only that it was handled externally. If the ethics process needs a time, it has
to come from the signed form, not from the data files.

### Phase 7 (participant identity, H1–H5) — complete, 5 Aug 2026

Participant IDs are now **entered by the researcher**, not generated. Before this, a person's ID
was `session_<timestamp>` plus a player index, which is unique per run and therefore cannot
identify a person at all: someone playing their second treatment produced a completely unrelated
ID, and the two sessions had nothing to join on. Since the owner's plan is for participants to
play their individual treatments on separate computers, no amount of after-the-fact analysis
could have reconstructed the link.

Two new files, both deliberately small:

- **`scripts/ResearchConfig.gd`** — study-design parameters that are not game mechanics: the group
  size and the participant-to-group mapping. Kept out of `PersonalityConfig`, which holds values
  that feed the routing model, so that changing a research protocol setting cannot be mistaken for
  changing a model parameter.
- **`scripts/ParticipantStore.gd`** — what is known about a participant across sessions on this
  machine: survey responses, α, and which treatments they have played. Separate from `DataLogger`,
  which writes the append-only research record and is never read back. Confusing the two would be
  a serious error, so they share no code.

Design points worth not relitigating:

- **The survey-skip rule is "do we already know this participant", not "is this treatment 1".**
  That single rule produces the right behaviour on both paths without any branch on treatment: a
  returning participant on their own machine is recognised and skipped, while the shared
  group-session machine has never seen them and asks. When *Conflict 6* is answered, only the
  store changes; the flow does not.
- **α provenance is logged** as `alpha_source`: `survey` when answered in this session, `stored`
  when reused. A reused set of responses is a copy of the original, not an independent second
  measurement, and analysis must not treat it as one.
- **Why reuse matters beyond convenience:** α is the mean of four items and is bucketed by
  threshold. Re-asking risks slightly different answers pushing a participant across a boundary,
  so their two sessions would run at different stress sensitivities — and any behaviour change
  between treatments would then have two possible causes with no way to separate them. That
  confound sits directly on the study's primary comparison, not on a side metric.
- **Duplicate IDs block the start.** Two people sharing a number would have their stored records
  merged, which is not recoverable once sessions have been run.
- **A treatment is recorded as played only when the game actually begins**, so abandoning at the
  menu does not consume a participant's position in the fixed order.
- **A malformed or partial stored record reads as absent**, and the survey is asked again. The
  cost is a few minutes; refusing to start because a cache file is corrupt would strand a
  participant who is sitting there ready to play.

**Participant IDs are free text** (owner preference, 5 Aug), not numbers. That is why the group
gets its own field rather than being derived: arithmetic derivation only works on numbers, and an
ID like `P07` cannot resolve to a group. The suggestion mechanism covers the numeric case and
stays silent otherwise.

Verified by a headless harness, 33 checks, all passing: ID validation including rejection of path
characters, the group suggestion firing on numeric IDs and staying blank on non-numeric ones or on
IDs spanning two groups, the store round-tripping a text ID with a "Don't know" response, the
treatment ordinal advancing across sessions, a malformed record degrading to "absent", the logger
recording the entered group and falling back on a blank one, the session ID staying distinct from
the group ID, and on the menu itself: Start blocked with nothing typed, one field per player,
auto-fill, duplicate and illegal IDs blocking Start, a manually typed group surviving later ID
edits, and the typed values arriving unchanged. The harness was removed after passing.

Note for the session protocol: the store is **per machine**. Participant records do not travel, so
a participant's second treatment must be run on the same computer as their first for the survey to
be skipped. That is exactly the constraint *Conflict 6* is about.

### Group treatment uses a default personality — 5 Aug 2026

**Owner decision:** *"for treatment 3, we are going to use an average personality for the algorithm
for each player to skip the friction of asking them all the surveys again."* This closes
*Conflict 6*.

The group treatment no longer runs the opening survey at all. Every player is assigned the average
stress sensitivity, and each affected row carries `alpha_source = "default"`. It applies to every
player rather than only those without a stored record, so the whole group runs at one sensitivity
instead of one member differing because they happened to play an earlier treatment on that machine.

`ResearchConfig.GROUP_TREATMENT_USES_DEFAULT_ALPHA` is the single flag governing it. Setting it to
`false` restores surveying with no other change, because the queue already asks anyone the machine
has no record for.

Three properties worth keeping:

- **A defaulted session writes no participant record.** Nothing was measured, so writing one would
  let an assumed value be mistaken for a real survey the next time that person plays.
- **Individual treatments are untouched.** T1 and T2 still survey a first-time participant and
  still reuse a stored value for a returning one.
- **The value is distinguishable in the log.** `alpha_source` separates `survey`, `stored` and
  `default`, and a defaulted row carries an empty response set rather than invented answers.

⚠️ **This is a sanctioned exception to guardrail 1** ("treatment is display only") — the one place a
treatment changes a routing input rather than only what is shown. Do not remove the branch as a
guardrail violation, and do not read it as licence for other treatment branches.

⚠️ **Accepted analytical cost.** Raised twice before the decision. A participant whose individual
sessions ran at cautious (α 3.0) or confident (α 0.4) sensitivity will experience their own commute
differently in the group session, so a change in how they invest between their individual and group
sessions has more than one possible explanation, and that sits on the study's primary comparison.
The `alpha_source` marking is the mitigation: those participants stay identifiable and can be
separated in analysis.

Verified by a headless harness, 17 checks, all passing: the survey never appearing in the group
treatment, all players receiving the average value marked `default`, no invented responses, no
participant record written, T1 and T2 still surveying, a returning participant still being skipped
and marked `stored`, the branch firing for the group treatment only, and an empty response set
scoring as the scale's neutral point rather than zero. The harness was removed after passing.
