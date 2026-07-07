# nfrf_games — CycleCity
Games developed for the NFRF Exploration project "Social Innovation in Engineering for Climate-Neutral Cities"

Godot Version 4.6.2

---

## Architecture Overview

```
GameManager (Node, autoload or scene root)
├── CityNetwork        — graph data + Dijkstra (pure data class, no Node)
├── Player             — one player's state, budget, route cache (pure data class)
├── DataLogger (Node)  — writes JSON logs for research analysis
└── [UI scenes]        — connect to GameManager signals, never read state directly
```

## Files

| File | What it does |
|---|---|
| `GameManager.gd` | State machine: rounds, treatments, AI bots, signal bus |
| `CityNetwork.gd` | Downtown Calgary road graph, Link data, Dijkstra routing, city metrics |
| `Player.gd` | Budget, upgrade actions, per-round log, Prospect Theory helpers |
| `DataLogger.gd` | Connects to GameManager signals, writes session JSON |

---

## How to Wire It Up in Godot

### 1. Scene setup

```
Main.tscn
└── GameManager (script: GameManager.gd)
    └── DataLogger (script: DataLogger.gd)
```

In `GameManager._ready()` connect DataLogger signals:
```gdscript
$DataLogger.treatment = treatment
round_ended.connect($DataLogger.on_round_ended)
game_over.connect($DataLogger.on_game_over)
```

### 2. Starting a game (from your menu scene)

```gdscript
# After pre-survey collects alpha:
var gm: GameManager = get_node("/root/GameManager")
gm.start_game(
    1.2,                                   # alpha from survey (stress sensitivity)
    GameManager.Treatment.COLLECTIVE_INFO   # T2
)
# Home (Eau Claire) and Work (Stampede Park) are set by the map.
```

### 3. Player submits upgrades (from your grid UI)

```gdscript
var upgrades = [
    { "link_id": "2,1-3,1", "level": 2 },   # protected track
    { "link_id": "1,0-2,0", "level": 1 },   # painted lane
]
GameManager.submit_upgrades(upgrades)
```

### 4. Listening to results (in your HUD scene)

```gdscript
GameManager.round_ended.connect(func(round_num, results):
    $TimeLabel.text = "%.1f min" % results["personal_time"]
    $SafetyLabel.text = "Safety: %.0f" % results["personal_safety"]
    # T2/T3 only:
    if results.has("city_avg_time"):
        $CityTimeLabel.text = "City avg: %.1f min" % results["city_avg_time"]
)
```

---

## Key Design Decisions

**No hardcoded routes.** `CityNetwork.find_route()` runs Dijkstra fresh every round. Upgrade a link → its `beta` drops → impedance drops → Dijkstra may switch routes automatically. This is the core research mechanic.

**Impedance formula:** `base_time × (1 + α × base_stress × β)` where:
- `α` = player personality (from pre-survey, never changes)
- `β` = infrastructure quality (player upgrades this, starts at 1.0)
- `base_stress` = LTS-derived road stress (never changes)

**Treatment flag controls UI, not logic.** All three treatments run identical routing and budgeting. The treatment flag only gates which metrics are *shown* to the player.

**DataLogger is signal-driven.** GameManager emits signals; DataLogger listens. Neither knows about the other's internals.

**Simulated residents use fixed seed 42.** Research validity requires the same city every session so results across participants are comparable.
