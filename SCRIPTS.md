# Scripts: where things live

One line per file. Class names match file names, so `CityGrid` is `scripts/ui/CityGrid.gd`.
Before changing the model or anything that gets logged, read **Guardrails** in `README.md`,
and run the probes afterwards (commands under **Probes** in `README.md`).

## Where to change what

| To change | Go to |
|---|---|
| Rider types: alpha values, survey score thresholds | `scripts/PersonalityConfig.gd` |
| Relief (beta) per upgrade level | `CityNetwork.beta_for()` |
| Impedance formula, lane speed bonus | `CityNetwork.gd`: `Link.impedance()`, `Link.TIME_FACTOR` |
| Upgrade prices, budget per round | `Player.gd`: `COST_PER_METRE_PAINTED`, `COST_PER_METRE_PROTECTED`, `DEFAULT_BUDGET_PER_ROUND` |
| Number of rounds | `GameManager.total_rounds` |
| Map nodes, roads, road stress | `CityNetwork.gd`: `NODES`, `EDGES` |
| Player home and work, resident commutes | `CityNetwork.gd`: `HOME_WORK_PAIRS`, `RESIDENT_COMMUTE_PAIRS` |
| Roads that start already upgraded | `CityNetwork._apply_initial_infrastructure()` |
| Safety score formula | `Player.gd`: `SAFETY_TARGET_DEFICIT`, `route_safety()` |
| How safety shows as stars | `scripts/ui/SafetyDisplay.gd` |
| What happens when a round ends | `GameManager._recalculate_and_end_round()` |
| Survey wording (signed off, keep verbatim) | `scripts/ui/SurveyQuestions.gd` |
| Survey answer scale and scoring | `scripts/ui/SurveyScale.gd` |
| Intro and instructions text | `scripts/ui/NarrativeIntro.gd` |
| City-wide messages (T2, T3) | `scripts/ui/CityFeedback.gd` |
| Better and worse arrows | `scripts/ui/Valence.gd` |
| Any colour | `scripts/Palette.gd` (button and panel styles also in `resources/ui_theme.tres`) |
| Road drawing: width, lanes, cars, route arrows | `scripts/ui/LinkSegment.gd` |
| Map pins and icons | `scripts/ui/NodeMarker.gd` |
| Legend | `scripts/ui/MapLegend.gd` |
| HUD buttons, round banner, first-round hint | `scripts/ui/GameHUD.gd` and `scenes/ui/GameHUD.tscn` |
| Researcher setup menu | `scripts/ui/MainMenu.gd` |
| Zoom, pan, touch | `scenes/main.gd` (and `scripts/MapGestures.gd`) |
| Sounds | `scripts/Audio.gd` |
| A logged value | Written in `DataLogger.gd`, CSV column declared in `LogSchema.gd`. Add columns, never rename them |
| Study, pilot and test session kinds | `scripts/ResearchConfig.gd` |
| Participant or group ID format | `scripts/ParticipantId.gd`, `scripts/GroupId.gd` |
| Where data is saved, the export zip | `DataLogger.SESSIONS_ROOT`, `scripts/SessionExporter.gd` |

## Every script

### Model (`scripts/`)

| File | What it does |
|---|---|
| `GameManager.gd` | Autoload. Runs the game: starts it, takes upgrades, ends each round, runs the simulated residents, emits the signals the UI listens to. |
| `CityNetwork.gd` | The board: nodes, roads, the `Link` class (time, stress, impedance), `beta_for()`, upgrades, coverage. |
| `Dijkstra.gd` | Shortest path on impedance. The path it returns is the rider's route. |
| `Player.gd` | One rider: home and work, alpha, budget, purchases, route, safety score, per-round log. |
| `PersonalityConfig.gd` | Alpha and protected-lane beta for each rider type, and the survey thresholds that pick the type. |

### Session and data (`scripts/`)

| File | What it does |
|---|---|
| `DataLogger.gd` | Writes the session folder: `events.json` and the CSVs. Created by `scenes/main.gd`, one per session. |
| `LogSchema.gd` | Every CSV column, declared once with its description. The codebook is built from it. |
| `SessionQueue.gd` | Carries the queued T2 across the scene reload in a T1 then T2 sitting. |
| `SessionExporter.gd` | Zips every session folder and reports where the zip landed. Needed on Android. |
| `ParticipantStore.gd` | Remembers a participant's opening survey and which treatments they have played, on this machine. |
| `ParticipantId.gd` | Issues and checks participant IDs like `PCY-XA6`. The last character catches typos. |
| `GroupId.gd` | Assigns group IDs (`PG01`, `PG02`) for the group treatment. |
| `ResearchConfig.gd` | Study settings that are not game mechanics: session kinds and ID rules. |

### Scene coordinator (`scenes/`)

| File | What it does |
|---|---|
| `main.gd` | Runs a session on `main.tscn`: menu, surveys, intro, chaining T1 into T2, staging upgrades before they are bought, map zoom and pan. |

### Map (`scripts/ui/` unless noted)

| File | What it does |
|---|---|
| `CityGrid.gd` | Builds and updates the map: background, roads, pins, route highlights, view modes, round-end animation. |
| `LinkSegment.gd` | One road: width by stress, lanes, cars, centre line, route band and arrows, click and tap. |
| `NodeMarker.gd` | One junction pin: home, work, resident home, workplace or plain, in seat colour. |
| `ProceduralBackground.gd` | The flat map background, drawn from the road layout. |
| `BikeIcon.gd` | The bike that travels each route in the round-end animation. |
| `MapLegend.gd` | The legend popover. Draws its swatches from the map's own constants. |
| `scripts/MapGestures.gd` | Tells roads a two-finger pinch is in progress so they do not open. |

### Screens (`scripts/ui/`, each on the scene of the same name in `scenes/ui/` unless noted)

| File | What it does |
|---|---|
| `MainMenu.gd` | Researcher setup: session type, treatment, IDs, group, player count, data folder, export, quit. |
| `NarrativeIntro.gd` | The five-page intro, reopenable from the Instructions button. |
| `LaneDiagram.gd` | The lane cross-section drawings in the intro. No scene of its own. |
| `GameHUD.gd` | Everything over the map during play: budget, travel time and stars, city card, rail buttons, round banner, hint, End Round. |
| `UpgradePopup.gd` | Choosing painted or protected for one road. |
| `RoundSummary.gd` | End-of-round panel: time, stars, changes, city results. |
| `EndScreen.gd` | Final results, shown just before the closing survey. |
| `PreSurvey.gd` | Opening survey. Its answers set the rider's alpha. |
| `PostSurvey.gd` | Closing survey, one seat at a time in a group. |
| `SurveyIdentityBanner.gd` | Seat colour, number and ID at the top of each survey. No scene of its own. |
| `SessionSavedDialog.gd` | Tells the researcher what was saved when a session ends. No scene of its own. |

### Shared helpers (`scripts/ui/` unless noted, no scene)

| File | What it does |
|---|---|
| `scripts/Palette.gd` | Every colour, plus `seat_color()`. |
| `SafetyDisplay.gd` | Turns a safety score into stars (route scale and single-road scale) and the debug number. |
| `CityFeedback.gd` | The city-wide lines shown in T2 and T3, worded the same as the log records them. |
| `Valence.gd` | Better or worse, and how that is shown: ▲ better, ▼ worse, teal or red. |
| `PlayerRow.gd` | The one-line-per-seat rows on the round summary and the end screen. |
| `SurveyQuestions.gd` | Survey wording, verbatim from the owner's question file. Do not paraphrase. |
| `SurveyScale.gd` | The six-point answer scale, its scoring, and the question and answer rows. |
| `scripts/Audio.gd` | Autoload. Hover, click and upgrade sounds, attached to every button automatically. |

### Tools (`tools/`)

| File | What it does |
|---|---|
| `probe_participant_id.tscn` | Checks the ID check character catches substitutions and transpositions. |
| `probe_group_id.tscn` | Checks group numbering, the menu row, and that browsing the menu uses up no numbers. |
| `probe_safety_stars.tscn` | Checks the stars track the score and the map's stress matches the model's. |
| `probe_round_summary.tscn` | Checks the round and end panels fit on screen on the frame they appear. |
| `probe_survey_identity.tscn` | Checks each seat gets its own colour and ID, and that surveys do not hide themselves. |
| `probe_hud.tscn` | Checks the round banner, the first-round hint, the selected-road highlight and overlay text contrast. |
| `check_session.py` | Checks one session folder straight after it is recorded. |
| `aggregate_logs.py` | Combines every session into analysis datasets. |
| `replay_upgrades.py` | Works out what each single upgrade did, from a finished session. |
| `README.md` | How the logs are laid out and how to use these tools. |

### Not scripts, but you will edit them

| File | What it does |
|---|---|
| `scenes/**/*.tscn` | Layout of every screen. A UI script's node positions and sizes live here. |
| `resources/ui_theme.tres` | Button, panel and field styles for the whole project. Mirrors `Palette.gd` by hand. |
| `assets/shaders/icon_tint.gdshader` | Recolours the black SVG icons. |
