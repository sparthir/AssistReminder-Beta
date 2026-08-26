# AssistReminder — Build Specification & Staged Test Plan

Version: 1.0
Audience: an independent coder or coding AI building the plugin from scratch.
Plugin folder: `AssistReminder/` (entry `Main.lua`, popup in `ReminderWindow.lua`,
strings in `Locale.lua`).  A manifest file called `AssistReminder.plugin` should be in the parent folder of the `AssistReminder/` folder.

---

## 1. Goal

When the local player is the **leader of a fellowship of 2+ members** and **no
assist target is set**, show a popup reminding them to set one. The popup is
dismissed with the OK button or the Escape key.

## 2. Hard Rules (violations = automatic FAIL)

| # | Rule |
|---|------|
| R1 | **Polling only.** All state detection uses the Lua API on a timer. NEVER parse chat messages (`Turbine.Chat.Received` must never be used). |
| R2 | **No slash commands, ever.** No `Turbine.Shell.AddCommand`. |
| R3 | **API source of truth:** the official SSG U25 docs at `G:\My Drive\coding\LotRO\SSG_U25_LuaDocumentation\` (`index.html`). Verify every method name/signature there before use. Do not guess. |
| R4 | **No persistent bindings to the Party object.** Never assign event handlers (`party.X = fn`) and never write properties to a Party object. Read-only bursts only. (History: persistent hooks surviving leadership transfer caused hard client crashes.) |
| R5 | Wrap every game-API call in `pcall`; log failures via the `Log()` helper (`[AssistReminder] ...` prefix) instead of crashing. |
| R6 | No game-state API calls inside `Turbine.Plugin.Load` — defer until the update loop runs. `Turbine.Plugin` has only `Load`/`Unload`; per-frame ticks come from a hidden `Turbine.UI.Window` with `SetWantsUpdates(true)` and an `Update` handler assigned **inside** `Plugin.Load` (the window does not exist before Load runs). |
| R7 | Lua 5.1 runtime. No external dependencies. All user-facing strings live in `Locale.lua`. |

### Known engine facts (verified by testing; cite in code comments)

- `Player:GetParty()` returns `Party` or `nil` when solo (docs:
  `Turbine_Gameplay_Player_GetParty.html`).
- `Party:GetLeader()` returns a **Player object**, not a string — compare via
  `GetLeader():GetName()` (docs: `Turbine_Gameplay_Party_GetLeader.html`).
- `Party:GetMemberCount()`, `Party:GetAssistTargetCount()` return integers.
- Assigning handlers onto Party objects and/or holding them across leadership
  transfers has produced hard client crashes, worst when the remote leader sets
  the LOCAL player as assist target. Hence R4.

---

## 3. Configuration

A single `FEATURES` table at the top of `Main.lua` controls behavior:

```lua
local FEATURES = {
    pollInterval  = 1.0;   -- seconds between state polls (default 1s)
    reShowOnClear = true;  -- true: reminder re-shows if targets are cleared
                           --       again in the same fellowship
                           -- false: strictly once per fellowship formation
    debugChatLog  = false; -- diagnostic logging of poll results
};
```

Every stage below lists which FEATURES keys it introduces.

---

## 4. Build stages

Build the stages IN ORDER. Each stage is independently testable. **Checkpoint
rule:** do not start stage N+1 until every test case of stages 1..N passes.
Reload between edits with `/plugins unload AssistReminder` then
`/plugins load AssistReminder`. All output appears in chat prefixed
`[AssistReminder]`.

---

### Stage 1 — Plugin skeleton & load/unload lifecycle

**Feature:** plugin manifest loads; Load/Unload handlers run without error.

**Requirements:**
- Valid `.plugin` manifest (`Package` points at the Main script).
- `Turbine.Plugin.Load` / `Unload` defined; both bodies wrapped in `pcall`.
- Load logs `Loaded.`; Unload clears handlers it set, no errors.

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T1.1 | Solo | Load plugin | `[AssistReminder] Loaded.` appears; no red Lua errors |
| T1.2 | Loaded | Unload plugin | No errors in chat |
| T1.3 | Loaded | Load twice without unloading | Clean replace or pcall-caught error (no crash) |

---

### Stage 2 — Update ticker (hidden window)

**Feature:** per-frame tick via hidden window; elapsed-time counter; simple
scheduler (`ScheduleOnce(delay, fn)`).

**FEATURES introduced:** *(none)*

**Requirements:**
- Hidden 1×1 `Turbine.UI.Window`: opacity 0, mouse-invisible,
  `SetWantsUpdates(true)`.
- The `Update` handler MUST be assigned inside `Plugin.Load` (R6).
- `elapsed` accumulates `args.DeltaTime` (fallback 0.05 if args missing).
- Scheduler stores `{time, fn}`; due callbacks run inside `pcall`.

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T2.1 | — | Load | No "attempt to index nil" errors (regression: original bug) |
| T2.2 | Schedule a log for t+2s at init | Wait 3s | Log appears once, ~2s after load, not immediately |
| T2.3 | Schedule two callbacks same delay | Wait | Both run, exactly once each |
| T2.4 | Callback that throws | Wait | Error swallowed by pcall; later scheduled items still fire |

---

### Stage 3 — Deferred local-player init

**Feature:** obtain `LocalPlayer.GetInstance()` and our own name AFTER load,
via the ticker (not inside `Plugin.Load`).

**FEATURES introduced:** *(none)*

**Requirements:**
- At first tick where `elapsed >= 2`: get instance, cache
  `myName = localPlayer:GetName()`, log it. Guarded by `pcall`.

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T3.1 | Solo | Load, wait 3s | `[AssistReminder] Watching. My name: <exact character name>` |
| T3.2 | — | Compare logged name vs actual character name | Identical incl. spacing/case (this string is compared against GetLeader later — any mismatch breaks Stage 6) |

---

### Stage 4 — Polling engine

**Feature:** repeated state polls on `FEATURES.pollInterval` using the
scheduler. Each poll is a self-contained function `PollState()`.

**FEATURES introduced:** `pollInterval`, `debugChatLog`.

**Requirements:**
- Poll reschedules itself every `pollInterval` seconds indefinitely.
- This stage's poll body ONLY logs that it fired (no API calls yet).
- Rescheduling must not depend on the poll body succeeding (pcall around the
  body; reschedule happens regardless).

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T4.1 | `pollInterval = 1.0` | Load, wait ~10s | ~10 poll logs at ~1s spacing (±0.3s tolerance) |
| T4.2 | `pollInterval = 5` | Reload, wait 12s | ~2-3 polls at 5s spacing |
| T4.3 | Make one poll throw (temporary test line) | Wait 3 intervals | Subsequent polls still occur |
| T4.4 | Unload while polling | `/plugins unload` | No errors; no further polls after unload |

---

### Stage 5 — Party snapshot (read-only burst)

**Feature:** each poll performs ONE read-only burst:
`GetParty()` → if present: `GetLeader():GetName()`, `GetMemberCount()`,
`GetAssistTargetCount()`. Store results in module state; drop the party
reference immediately (R4: nothing persists).

**FEATURES introduced:** uses `debugChatLog` for verbose output.

**Requirements:**
- Entire burst inside one `pcall`.
- NO handler assignment, NO property writes on the Party object (R4).
- Burst results land in: `inFellowship`, `leaderName`, `memberCount`,
  `assistTargetCount`.

**Test cases:**

| ID | Setup | Action | Expected (within ~1 poll interval) |
|----|-------|--------|-------------------------------------|
| T5.1 | Solo | Load | `inFellowship = false`; no crash |
| T5.2 | 2-person fellowship, YOU lead | Observe polls | `inFellowship = true`, `leaderName == your name`, `memberCount = 2`, correct target count |
| T5.3 | 2-person fellowship, OTHER leads | Observe polls | Same but `leaderName == their name` |
| T5.4 | You lead; leader adds/removes assist targets | Watch polls | `assistTargetCount` tracks changes within one interval |
| T5.5 | Member joins (2→3) | Watch polls | `memberCount` becomes 3 within one interval |
| T5.6 | Disband | Watch polls | `inFellowship = false` within one interval |
| T5.7 | Run 10+ min under REMOTE leadership with targets set/removed repeatedly | Observe | **No client crash** (validates the R4 snapshot design) |

---

### Stage 6 — Leadership detection

**Feature:** derive boolean `amLeader` from each snapshot:
`amLeader = inFellowship and leaderName == myName`.

**FEATURES introduced:** *(none)*

**Requirements:** pure comparison of cached strings; no extra API calls.

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T6.1 | Solo | Load | `amLeader = false` |
| T6.2 | You lead | Poll | `amLeader = true` |
| T6.3 | Other leads | Poll | `amLeader = false` |
| T6.4 | Transfer leadership you→them | Watch polls | flips to false within one interval |
| T6.5 | Transfer back them→you | Watch polls | flips to true within one interval |
| T6.6 | Rename-sensitivity spot check | Verify logged leaderName equals logged myName when you lead | Strings identical (guards against trailing-space mismatches) |

---

### Stage 7 — Reminder condition (pure logic)

**Feature:** pure function `ShouldRemind(state)` → boolean.
Condition: `amLeader AND memberCount >= 2 AND assistTargetCount == 0`.
Implement as its own function so it can be reasoned about/tested in isolation.

**FEATURES introduced:** *(none)*

**Test cases (truth table — verify via debug log of the decision):**

| ID | amLeader | members | targets | ShouldRemind |
|----|----------|---------|---------|--------------|
| T7.1 | false | 2 | 0 | false |
| T7.2 | true | 1 | 0 | false (solo "fellowship") |
| T7.3 | true | 2 | 0 | **true** |
| T7.4 | true | 2 | 1 | false |
| T7.5 | true | 6 | 0 | true |
| T7.6 | true | 2 | nil (read failed) | false (treat unknown as "has targets") |

---

### Stage 8 — Popup window UI

**Feature:** the reminder window itself, shown/hidden on command from logic.
File: `ReminderWindow.lua`, class `AssistReminderReminderWindow`
(`Turbine.UI.Lotro.Window`).

**FEATURES introduced:** *(none)*

**Requirements:**
- Title bar text, heading label, body label, centered OK button (all strings
  from `Locale.lua`).
- `SetWantsKeyEvents(true)` so Escape reaches the window; Escape dismisses.
- `Show()` makes visible + activates; `Dismiss()` hides and invokes optional
  `onDismiss` callback (pcall'd).

**Test cases:**

| ID | Setup | Action | Expected |
|----|-------|--------|----------|
| T8.1 | Temporarily auto-show 5s after load | Load | Window appears, readable, correct texts |
| T8.2 | Visible | Click OK | Window hides; no errors |
| T8.3 | Fresh load, visible | Press Escape (window focused) | Window hides |
| T8.4 | Dismissed | Re-call Show() | Shows again (reusability) |
| T8.5 | — | Check position | Window fully on-screen at default position |

---

### Stage 9 — One-shot / re-show policy

**Feature:** combine Stage 7 + 8 with dismissal memory.
- `reShowOnClear = true`: popup fires whenever the condition transitions from
  unmet→met (so clearing a target later re-triggers it).
- `reShowOnClear = false`: once shown for a given fellowship formation, never
  again until the fellowship is left/disbanded/re-formed (track via the
  `inFellowship` false→true edge).

**FEATURES introduced:** `reShowOnClear`.

**Test cases:**

| ID | Setup | Action | Expected (`reShowOnClear = true`) |
|----|-------|--------|-----------------------------------|
| T9.1 | Form fellowship, you lead, no targets | Within 1-2 polls | Popup shows once |
| T9.2 | Popup dismissed, condition unchanged | Wait 10+ polls | Does NOT reappear (edge-triggered, not level-triggered) |
| T9.3 | Set assist target | Wait | No popup |
| T9.4 | Remove assist target | Wait | Popup appears again |
| T9.5 | Dismiss; disband; re-form (you lead, no targets) | Wait | Popup appears again (new formation resets memory in BOTH modes) |
| T9.6 | `reShowOnClear = false`; repeat T9.1–T9.4 | — | T9.4 stays hidden; T9.5 still shows |
| T9.7 | You lead, member leaves (2→1) after dismissal | Wait | No popup (members < 2 blocks it) |

---

### Stage 10 — Leadership transfer robustness (integration)

**Feature:** everything above working across leadership churn — the scenario
that crashed earlier builds.

**Test cases (run each ≥ 3 times):**

| ID | Scenario | Expected |
|----|----------|----------|
| T10.1 | Load while leading → transfer away → remote leader adds THEMSELF as assist target | No crash; amLeader false; no popup |
| T10.2 | Load while leading → transfer away → remote leader adds YOU as assist target | **No crash** (historical crash case) |
| T10.3 | Remote leader holds leadership 5+ min, adds/removes targets/members repeatedly | No crash, no popup |
| T10.4 | Take leadership back with no targets set | Popup within 1-2 polls |
| T10.5 | Rapid leadership ping-pong ×5 | No crash; amLeader correct at rest |
| T10.6 | Leave fellowship, stay out 60s, rejoin as member (remote lead), then get promoted | No crash; popup only once leading + condition met |
| T10.7 | Raid conversion while leading, no targets | memberCount reflects raid size; logic stays sane |

---

## 5. Final acceptance checklist

- [ ] All stage checkpoints green, in order.
- [ ] R1–R7 audit: grep proves no `Turbine.Chat.Received`, no `AddCommand`,
      no `party.<event> =` assignments anywhere in the source.
- [ ] 30-minute soak: mixed leadership transfers + target add/removes +
      joins/leaves — zero crashes, zero uncaught Lua errors.
- [ ] Every user-visible string lives in `Locale.lua` (none hard-coded).

## 6. Reporting format (per stage)

For each test ID report: PASS/FAIL, exact chat lines observed, any red Lua
error text, any client crash + the action that triggered it. A stage is done
only when ALL of its IDs pass.

---

## 7. Reference examples from installed plugins

Study these installed plugins before coding. They are battle-tested against
this same engine and demonstrate the idioms this project should follow.

### 7.1 Folder & file structure conventions

Observed across `Plugins/TravelWindowII`, `Plugins/DigitalUtopia/Palantir`,
`Plugins/TurbinePlugins/Vitals`, `Plugins/HabnaPlugins/TitanBar`:

```
Plugins/
  <AuthorOrPlugin>/                      <- author namespace folder
    <PluginName>.plugin                  <- manifest NEXT TO the code folder
    <PluginName>/                        <- code package folder
      __init__.lua                       <- imports all support files FIRST
      Main.lua                           <- entry point; Package ends in ".Main"
      OneFilePerComponent.lua            <- window class, logic modules, etc.
      Locale*.lua / Locale/              <- all user-facing strings
      Resources/                         <- .tga icons/images only
      data/ or utils/                    <- optional supporting data/helpers
```

Key conventions to follow:

| Convention | Example | Notes |
|------------|---------|-------|
| Manifest `<Package>` mirrors folder path + `Main` | `TravelWindowII.src.Main`, `TurbinePlugins.Vitals.Main` | Our current `Sparthir.AssistReminder.Main` already conforms |
| `__init__.lua` imports support files so classes exist before Main runs | Vitals, Palantir, AssistReminder (already done) | Import order matters: Locale → components → Main |
| One class per file, file named after the class | Palantir (`MainWindow.lua`, `ToggleButton.lua`), Vitals (`VitalsWindow.lua`) | Keep `ReminderWindow.lua` pattern; split future features into their own files |
| Manifest metadata: Name, Author, Version, Description, optional `<Image>` (.tga icon) | `TravelWindowII.plugin` | Consider adding a `<Image>` icon later |
| Optional `<Configuration Apartment="...">` for per-plugin option storage | `TravelWindowII.plugin` | Only needed if options panels are added |

**Target structure for AssistReminder** (matches conventions; current files map
directly):

```
Sparthir/
  AssistReminder.plugin
  AssistReminder/
    __init__.lua          -- imports Locale + ReminderWindow
    Locale.lua            -- user-facing strings
    Main.lua              -- entry point, polling/detection logic
    ReminderWindow.lua    -- popup UI class
    (future:) Poller.lua, StateMachine.lua ... one concern per file
```

### 7.2 API usage patterns worth copying

| Pattern | Where to look | What to copy |
|---------|---------------|--------------|
| Window + control construction (labels, buttons, fonts, colors) | `Plugins/DigitalUtopia/Palantir/MainWindow.lua`, `Plugins/TurbinePlugins/Vitals/VitalsWindow.lua` | Parent/size/position/font/alignment idiom; `Turbine.UI.Lotro.Window` subclassing |
| Key event handling for Escape dismissal | Palantir windows | `SetWantsKeyEvents(true)` + `KeyDown` handler checking `args.Key == Turbine.UI.Keys.Escape` |
| Plugin lifecycle via `Plugins["<Name>"]` object | `TravelWindowII/src/Main.lua` (`Plugins["Travel Window II"].Load = ...`) | Alternative to `Turbine.Plugin.Load`; both valid — we use `Turbine.Plugin.*` |
| Settings persistence | `Palantir/OptionsManager.lua`, TitanBar (`Turbine.PluginData.Save/Load(Turbine.DataScope.Account, key, value)`) | If poll interval or reShowOnClear should persist between sessions, use `Turbine.PluginData` with an Account-scope table. Wrap in pcall (known EU-client quirk — see `TravelWindowII/src/VindarPatch.lua`) |
| Options panel integration (game Options → Plugins panel) | `TravelWindowII/src/OptionsPanel.lua` | Only if a settings UI is ever wanted; not required by this spec |
| Self-rescheduling timers | Any plugin using a hidden window's `Update` with DeltaTime accumulation | Our Stage 2 ticker follows this exact idiom |

### 7.3 Anti-patterns observed elsewhere (do NOT copy)

- `TravelWindowII/src/Main.lua` executes game-API calls (`LocalPlayer.GetInstance()`,
  skill list reads) at **file scope** — works there but violates our R6
  deferral rule and is exactly the pattern that produced this plugin's original
  nil-index crash. Always defer.
- Slash commands (`Turbine.ShellCommand`) — banned here by R2.
- Chat parsing for state detection — banned here by R1.

