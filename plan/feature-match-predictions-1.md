---
goal: Estimate likely outcomes for upcoming matches and explain the factors
version: 1.2
date_created: 2026-10-31
last_updated: 2026-11-01
owner: my-football maintainers
status: 'Proposed'
tags: [feature, fixtures, prediction, standings, ai]
---

# Introduction

A long press on an upcoming fixture opens a prediction sheet. The sheet shows:

- the estimated chance of a home win, a draw and an away win (sum = 100%);
- a verdict: home win, away win, or "Close – draw likely";
- a "Why this estimate?" list of the factors behind the numbers;
- notes on missing or partial data, and a disclaimer.

Dart code calculates the numbers and the reasons. The calculation is
deterministic: the same inputs always give the same result. Gemini Nano
(on-device AI) is optional. It may only rewrite the computed reasons as prose.
It never picks the outcome. The feature works fully without AI.

The v1 feature makes **no new API calls** beyond data the app already loads
and caches (standings and season events).

### Changes in v1.2 of this plan

- Recent form now gives newer matches more weight (§4.1). A team that won its
  last 3 gets a better form score than a team with the same 3 W / 2 L that
  lost its last 2.
- The weighting is used only when the order of the results is known. It is
  always known for season-event form. For `strForm` it is known only after
  TASK-019 confirms the letter order. Otherwise the formula falls back to
  plain counts and the sheet says so.
- TASK-019 is now required and moves to Phase 1, before the calculator.
- New "streak" reason line (for example "Arsenal have won their last 3").
  It is display only and does not change the numbers a second time.
- `PredictionWeights.recencyWeighting` switches the weighting on and off, so
  the back-test (TASK-024) can compare weighted form with plain counts.

### Changes from v1.0 of this plan

- Recent form now comes first from the cached season events (the same method
  `TeamDetailScreen` uses), with `strForm` as the fallback. v1.0 suggested
  `eventslast.php`; that endpoint is dropped from v1.
- (Changed again in v1.2.) v1.1 used only the W/D/L counts of the form.
- A concrete starting formula with constants and small-sample shrinkage.
- An explicit rule for when the verdict is a draw. With a plain "highest
  probability wins" rule, a draw is almost never the top outcome.
- Eligibility reuses the existing `MatchReminder.canRemind` rule.
- Team detail screen upcoming fixtures are in scope.
- Requirements and tasks use the REQ-/TASK- format of the other plans.
- Fixed `date_created` (it was in the future).

## 1. Findings in the current code

### Fixtures and gestures

- `FixtureTile` (`lib/features/fixtures/widgets/fixture_tile.dart`) is an
  `InkWell` with `onTap` and `onDoubleTap` only. No `onLongPress`.
- `FixturesView._MatchweekSection` wires the gestures. Finished: tap = goals
  sheet, double-tap = line-up. Upcoming: no tap, double-tap = reminder when
  `MatchReminder.canRemind(f)` is true.
- `TeamDetailScreen` also renders upcoming `FixtureTile`s with the same
  reminder double-tap. It should get the same long press.
- `MatchReminder.canRemind` already means "not postponed, not finished, not
  live, kickoff in the future". This is exactly the prediction eligibility rule.
- `FixturesRepository` defines "upcoming" as `!isFinished`, so the list can
  contain live and postponed matches. The gesture wiring must filter them.

### Data already available

- `TeamStanding`: `rank`, `points`, `goalsDiff`, `played`, `win`, `draw`,
  `lose`, `form` (`strForm`). Test fixtures show values like `"WWDWW"`. The
  order of the letters (oldest-first or newest-first) is not documented.
- `StandingsRepository.getStandings(league, season)` caches the table for 6 h
  under `standings_<league>_<season>`.
- `FixturesRepository` and `TeamRepository` share the cache key
  `season_events_<league>_<season>` (30 min TTL). It contains finished
  fixtures with scores.
- `Fixture.resultFor(teamId)` returns `W`/`D`/`L` for a finished fixture.
  `TeamDetailScreen` already builds a last-five form strip from this. That
  logic should move into a shared helper.
- Free key limits: `eventsseason` returns only ~15 events per season, so
  derived form is usually 0–2 matches. `eventslast` returns 1 event. A Premium
  key returns the full season, so derived form is complete.
- `lookuptable` can return one table for a multi-group competition. A rank
  comparison across groups is not meaningful; points per game still is.

### On-device AI

- `AiService` (`isAvailable`, `generate`) with `GeminiNanoService` on Android
  and `UnavailableAiService` elsewhere, via `aiServiceProvider`.
- `RecapBuilder` shows the pattern to copy: deterministic text first, an
  8-second timeout around availability check plus generation, validation of
  the output, and a prompt-version cache key.
- `validateRecapText` is specific to recaps. Predictions need their own
  validator.

## 2. Requirements and constraints

- **REQ-001**: A long press on an eligible upcoming fixture opens the
  prediction sheet, both in `FixturesView` and in `TeamDetailScreen`.
- **REQ-002**: Eligible means `MatchReminder.canRemind(fixture)` is true. Live,
  finished, postponed and past fixtures get no long-press action.
- **REQ-003**: The sheet shows home, draw and away percentages that sum to
  exactly 100% after rounding.
- **REQ-004**: The sheet shows a verdict using the rule in §4.4.
- **REQ-005**: Every reason in the list maps to one computed factor and
  quotes only numbers from the inputs.
- **REQ-006**: Missing data is reported as missing. It is never treated as a
  zero or a loss.
- **REQ-007**: If a team is not in the selected league table, the sheet shows
  "Not enough data" with the reason, and no percentages.
- **REQ-008**: The feature makes no new network calls beyond what
  `StandingsRepository` and `FixturesRepository` already do, including their
  caches.
- **REQ-009**: Tap and double-tap behavior stays unchanged.
- **REQ-010**: The sheet says "Estimate based on table and form. Not betting
  advice." The UI never says "calibrated" or "odds".
- **REQ-011**: The percentages are shown as text, not only as color, and the
  layout works with large text.
- **CON-001**: Prediction never depends on AI. AI prose, if shipped, is
  optional, validated and replaceable by the deterministic text.
- **CON-002**: A long press never triggers a Gemini Nano model download.
- **CON-003**: No match data leaves the device.
- **PAT-001**: Pure calculation in a plain Dart class, unit-testable without
  Flutter. Riverpod `FutureProvider.autoDispose.family` for loading, like
  `teamFixturesProvider`.

## 3. Architecture

```text
FixtureTile.onLongPress (eligible only)
  └─ showPredictionSheet(context, fixture)
       └─ predictionProvider(PredictionKey(fixtureId, leagueId, season))
            ├─ StandingsRepository.getStandings  (cached 6 h)
            ├─ FixturesRepository season events  (cached 30 min)
            ├─ PredictionInputBuilder  → PredictionInput (per-team factors + sources)
            └─ PredictionCalculator    → PredictionResult (probabilities, verdict, reasons)
       └─ optional: PredictionNarrator (AiService + validator + timeout)
```

New files:

```text
lib/features/predictions/
  team_form.dart                  # shared recent-form helper (also used by TeamDetailScreen)
  prediction_input.dart           # TeamFactors, PredictionInput, data sources
  prediction_result.dart          # probabilities, verdict, PredictionReason list
  prediction_calculator.dart      # pure formula, versioned
  prediction_repository.dart      # builds input from cached repositories
  prediction_providers.dart       # predictionProvider family
  prediction_sheet.dart           # showPredictionSheet + UI states
  prediction_prompt.dart          # Phase 5 only
  prediction_text_validator.dart  # Phase 5 only
```

The provider key holds `fixtureId`, `leagueId` and `season`. This prevents
stale results after a league or season switch. The fixture itself is passed
to the sheet; the provider looks it up again in the season events and fails
gracefully if it is gone.

## 4. Calculation (formula v1)

All constants are starting values. They live in one `PredictionWeights`
object with a `version` string (`'v1'`), so they can be tuned and tested.

### 4.1 Per-team factors

Let `L` be the league average points per game (from the table; fall back to
1.37 if the table has no games played).

1. **Points per game, shrunk.** With few games, pull the value toward the
   league average: `ppg = (points + k·L) / (played + k)`, `k = 3`. This stops
   "1 game, 3 points" from looking like a top team.
2. **Goal difference per game, shrunk toward 0:**
   `gdpg = goalsDiff / (played + k)`.
3. **Recent form (up to 5 results).**
   - Source A: the last finished fixtures for the team in the cached season
     events, before kickoff, newest 5, via `Fixture.resultFor`. Use this when
     it has ≥ 3 results.
     The order is always known (fixture dates).
   - Source B: `TeamStanding.form`, only if it matches `^[WDL]{1,5}$`
     (ignore other characters and case). The order is known only if the
     constant `standingsFormOrder` (set by TASK-019) is `newestFirst` or
     `oldestFirst`. While it is `unknown`, the order is not used.
   - Otherwise: form is missing.
   - **Recency-weighted points.** Sort the results newest first. Give them the
     weights `w = [1.0, 0.9, 0.8, 0.7, 0.6]` (only the first `n` are used).
     Points per result: W = 3, D = 1, L = 0.
     `formPpg = Σ(wᵢ · pointsᵢ) / Σwᵢ`.
     If the order is unknown, or `recencyWeighting` is off, every weight is
     1.0. This is the plain average.
   - Shrink toward the team's `ppg` for small samples:
     `formAdj = (n·formPpg + 2·ppg) / (n + 2)`.
   - Example (both teams 3 W / 2 L, plain average 1.8):

     | Last 5, newest first | Weighted `formPpg` |
     |----------------------|--------------------|
     | W W W L L (rising)   | 2.03 |
     | L L W W W (falling)  | 1.58 |

     Between otherwise equal teams, this moves the home-win chance from about
     44% to about 50%. The weights are deliberately gentle. Research shows
     that short streaks predict less than underlying strength. Steeper
     weights (for example 1.0 down to 0.2 gives 2.4 vs 1.2) would overrate a
     streak.
   - Record the source, `n`, whether the order was used, and the current
     streak (the same result in a row, newest first, length ≥ 2) for the
     reason text.
4. **Rank** is shown in the reasons, but is not in the formula. Points per
   game already carries the same signal and handles different games played.

### 4.2 Strength and home advantage

```text
strength = ppg + 0.25·gdpg + 0.35·(formAdj − ppg)     // missing form → last term = 0
d        = strength_home − strength_away + H           // H = 0.20 (home advantage, in ppg)
```

`H` is a documented constant. It does not come from the API.

### 4.3 Probabilities (ordered logistic)

```text
pHome = σ(a·d − c)
pAway = σ(−a·d − c)
pDraw = 1 − pHome − pAway
a = 1.6, c = 0.55, σ(x) = 1 / (1 + e^−x)
```

Reference values (home / draw / away):

| `d` | Meaning | Result |
|-----|---------|--------|
| 0.0 | away side better by exactly H | 37 / 27 / 37 |
| 0.2 | equal teams (only home advantage) | 44 / 26 / 30 |
| 0.5 | clear home favourite | 56 / 23 / 21 |
| 1.0 | top vs bottom | 74 / 16 / 10 |

A large `d` lowers the draw chance in a natural way. Display rounding uses the largest-remainder method so
the shown values sum to 100.

### 4.4 Verdict

A plain "highest probability" rule almost never picks a draw (the draw peaks
at about 27%). The user goal includes "or a draw is most likely", so the
verdict is:

- `|pHome − pAway| < 0.10` (about `|d| < 0.14`) → **"Close – draw likely"**.
  Equal teams therefore give "Home win – slight favourite" because of home
  advantage. The draw verdict appears when the away side is a little stronger
  and cancels the home advantage.
- otherwise the side with the higher probability → **"Home win"** /
  **"Away win"**, with "slight favourite" when the gap is < 0.20.

The sheet always shows all three percentages, so the verdict never hides the
numbers.

### 4.5 Reasons

Each factor creates one `PredictionReason { factor, favours (home/away/none),
text, numbers }`. Example texts:

- "Arsenal are 3rd, Fulham are 12th (2.1 vs 1.3 points per game)."
- "Fulham's recent form has the more favourable form adjustment: 10 of 15
  points vs 4 of 15, with recent matches counting more." (The wording names
  the side whose form term is higher after adjustment; it does not claim that
  side has the higher raw points, which can disagree.)
- "Arsenal have won their last 3." / "Fulham have lost their last 2."
  (streak lines, length ≥ 2, `favours` the team on a winning streak or
  against the team on a losing streak. Display only: the streak is already
  part of the weighted form, so it adds nothing to `d`.)
- "Recent form order is unknown for this league, so all 5 matches count
  the same." (shown when source B is used without a known order)
- "Home advantage is included as a fixed factor."
- "Recent form is missing for Arsenal." (missing factor, `favours: none`)

The reasons are sorted by their contribution to `d`, largest first.

### 4.6 Completeness

`completeness` is `full` (table plus form for both teams with n ≥ 3),
`partial` (table plus some form), or `tableOnly`. The sheet shows a note for
`partial` and `tableOnly`. Form with an unknown order still counts as form
for completeness, but adds the order note from §4.5. An early season (`played < 3` for either team)
adds the note "Early in the season – low confidence."

### 4.7 Evaluation

Today's table cannot be used to back-test past matches. Only a "table at that
time" can. v1 therefore ships as a heuristic estimate (REQ-010). Later, with a
Premium key, a back-test can rebuild the table round by round from the season
events. Report accuracy and Brier score against a fixed baseline (the
league's overall home/draw/away rates). Run it twice, with
`recencyWeighting` on and off. Keep the weighting only if it is at least as
good. This is TASK-024 and is optional.

## 5. Implementation steps

### Phase 1 – Shared helpers and pure calculation

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-019 | **Required, do first.** Learn the `strForm` letter order. With a Premium key (full season events), compare `TeamStanding.form` with `recentForm` for at least 5 teams in 2 leagues, after a match day. Set `const standingsFormOrder` in `team_form.dart` to `newestFirst` or `oldestFirst`, and record the evidence in this plan. If it is inconsistent or there is no Premium key, leave it `unknown` (counts only for source B). Add a test that pins the chosen value. | ✅ (kept `unknown`) | 2026-11-01 |
| TASK-001 | Create `lib/features/predictions/team_form.dart`: `enum FormOrder { newestFirst, oldestFirst, unknown }`; `const standingsFormOrder` (TASK-019); `List<String> recentForm(int teamId, Iterable<Fixture> events, {DateTime? before, int limit = 5})` returns W/D/L **newest first** from finished fixtures; `({List<String> results, bool ordered})? parseStandingForm(String raw)` returns null unless it matches `^[WDL]{1,5}$` (case-insensitive), and when the order is known normalizes the results to newest first; `int currentStreak(List<String> newestFirst)` returns the length of the leading run (0 if < 2). | ✅ | 2026-11-01 |
| TASK-002 | Refactor `TeamDetailScreen` to use `recentForm`. `recentForm` returns newest first, so reverse it for the existing oldest-to-newest form strip. Distinct kick-off times keep their chronological order; fixtures with the same kick-off time are now ordered by fixture id (newest first) instead of the order being left unspecified by the old comparator. | ✅ | 2026-11-01 |
| TASK-003 | Create `prediction_input.dart`: `FormSource { seasonEvents, standingsForm, none }`, `TeamFactors { teamId, name, rank, played, points, goalsDiff, List<String> form (newest first), bool formOrdered, FormSource formSource }`, `PredictionInput { fixture, home, away, leagueAvgPpg, sameGroup }`. | ✅ | 2026-11-01 |
| TASK-004 | Create `prediction_result.dart`: `Outcome { home, draw, away }`, `Verdict { homeWin, awayWin, closeDrawLikely }`, `PredictionReason`, `Completeness`, `PredictionResult { pHome, pDraw, pAway, displayPercents (int, sum 100), verdict, isSlight, reasons, missingNotes, completeness, formulaVersion }`, and `PredictionUnavailable { reason }`. | ✅ | 2026-11-01 |
| TASK-005 | Create `prediction_calculator.dart`: `PredictionWeights` (k = 3, gd = 0.25, form = 0.35, recency = [1.0, 0.9, 0.8, 0.7, 0.6], `recencyWeighting = true`, H = 0.20, a = 1.6, c = 0.55, version `'v1'`) and `PredictionCalculator.calculate(PredictionInput) → PredictionResult`, implementing §4.1–4.6, including largest-remainder rounding. | ✅ | 2026-11-01 |
| TASK-006 | Tests `test/features/predictions/team_form_test.dart` and `prediction_calculator_test.dart`: probabilities sum to 1 and display percents to 100; the reference values in §4.3 (±1 point); equal teams → home win, slight favourite; `d ≈ 0` → "Close – draw likely"; a stronger home team → home win; with H = 0, swapping the teams mirrors the result; missing form never lowers strength below table-only strength; `played = 0` does not divide by zero; invalid `strForm` is rejected; reasons quote only input numbers. Recency: WWWLL scores 2.03 and LLWWW scores 1.58 (newest first, ±0.01); unordered form or `recencyWeighting = false` gives 1.8 for both; with weighting, the rising team gets a higher home-win chance than the falling team, all else equal; streak lines appear for runs ≥ 2 and do not change the probabilities; the order note appears for unordered source B. | ✅ | 2026-11-01 |

TASK-019 outcome: `standingsFormOrder` stays `FormOrder.unknown` for v1.
No Premium key (full season events) was available in this environment, so
the `strForm` letter order could not be verified against derived recent
form. Per RISK-006 the safe default is kept: `strForm` counts only as an
unordered source (plain counts), and the pinned test in
`test/features/predictions/team_form_test.dart` keeps the value in place.
Revisit when Premium evidence exists.

### Phase 2 – Data and provider

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-007 | Add a public `Future<List<Fixture>> getSeasonEvents({league, season})` to `FixturesRepository` (wrapping the existing private `_seasonEvents`), so prediction code reuses the shared cache. | ✅ | 2026-11-01 |
| TASK-008 | Create `prediction_repository.dart`: `PredictionRepository(standings, fixtures)`. `Future<PredictionInput> build(...)` loads both cached sources in parallel and finds both teams by `teamId`. It throws `PredictionUnavailable` if either team is missing (REQ-007). It picks the form source per §4.1 and computes `leagueAvgPpg`. | ✅ | 2026-11-01 |
| TASK-009 | Create `prediction_providers.dart`: `predictionRepositoryProvider` and `predictionProvider = FutureProvider.autoDispose.family<PredictionResult, PredictionKey>`, with `PredictionKey = ({int fixtureId, int leagueId, int season})`. | ✅ | 2026-11-01 |
| TASK-010 | Tests `prediction_repository_test.dart` with fake repositories: team missing from the table; derived form preferred when ≥ 3 results; fallback to `strForm`; no form; standings API failure with a cached copy; no extra client calls beyond the two repositories (REQ-008). | ✅ | 2026-11-01 |

### Phase 3 – Long-press UI

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-011 | `FixtureTile`: add `final VoidCallback? onLongPress;` and pass it to `InkWell`. Add a semantics hint "Long press for prediction" when it is set. | ✅ | 2026-11-01 |
| TASK-012 | `FixturesView._MatchweekSection`: `onLongPress: MatchReminder.canRemind(f) ? () => showPredictionSheet(context, f) : null`. | ✅ | 2026-11-01 |
| TASK-013 | `TeamDetailScreen` upcoming list: the same wiring. | ✅ | 2026-11-01 |
| TASK-014 | Create `prediction_sheet.dart`: `showPredictionSheet` with `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)`, like the recap and reminder sheets. Content: teams and local kickoff; the verdict; a three-segment bar with labelled percentages ("Arsenal 52%", "Draw 24%", "Fulham 24%"); "Why this estimate?" reasons; missing-data and early-season notes; the disclaimer (REQ-010). States: loading, `PredictionUnavailable` (message), error (`ApiErrorView`). | ✅ | 2026-11-01 |
| TASK-015 | Widget tests `test/features/predictions/prediction_sheet_test.dart` and an addition to the fixture tests: a long press opens the sheet; a double-tap still opens the reminder sheet; live, postponed, finished and past fixtures have no long press; the sheet renders the percentages as text; there is no overflow at text scale 2.0. | ✅ | 2026-11-01 |

### Phase 4 – Docs and verification

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-016 | `README.md` fixtures and team sections: "Long press an upcoming match to see a predicted result and the reasons." Mention the estimate disclaimer and the free-key form limits. | ✅ | 2026-11-01 |
| TASK-017 | Run `flutter analyze` (zero new warnings) and `flutter test` (all pass). | ✅ | 2026-11-01 |
| TASK-018 | Manual check on the free key and a Premium key: the form source shown matches expectations, and the numbers look plausible for top-vs-bottom and mid-vs-mid matches. Needs a real device plus free and Premium API keys; cannot be verified in this environment, so it stays open. | | |

### Phase 5 – Gemini Nano prose (in scope; TASK-024 optional)

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-020 | `prediction_prompt.dart`: a versioned prompt (`predictionPromptVersion`) that contains only the verdict, the three percentages, the team names and the reason texts. Instruction: rewrite as 2–3 plain sentences; add no facts. | ✅ | 2026-11-01 |
| TASK-021 | `prediction_text_validator.dart`: reject the output if it contains a number not in the result, a team name not in the fixture, the words "odds"/"bet"/"guarantee", or more than 400 characters. | ✅ | 2026-11-01 |
| TASK-022 | `PredictionNarrator`: modeled on `RecapBuilder`. An 8 s timeout around `isAvailable` plus `generate`. It never calls a download (CON-002). It keeps one cache entry per fixture (`prediction_ai_{fixtureId}`) holding the formula version, the prompt version, a fingerprint of the exact prompt content and the text; on read all four must match, otherwise the entry is a miss and is overwritten after the next validated generation. The sheet shows the deterministic reasons at once and adds the AI summary above them only after validation passes. | ✅ | 2026-11-01 |
| TASK-023 | Tests with a fake `AiService`: unavailable, timeout, invented number, invented team, valid output. | ✅ | 2026-11-01 |
| TASK-024 | (Optional, Premium) Back-test script: rebuild the table per round from season events, predict each next round, and report accuracy and Brier score against the fixed baseline from §4.7, with `recencyWeighting` on and off. Adjust `PredictionWeights` (including the recency weights) and bump the version. | | |

## 6. Alternatives considered

- **ALT-001: `eventslast.php` per team for form.** Rejected for v1. It adds
  two uncached calls per long press, the free key returns only 1 event, and
  the 30 requests/min limit applies.
- **ALT-002: Gemini Nano picks the winner.** Rejected. It is not reproducible,
  not testable, Android-only, and it may invent facts.
- **ALT-003: Rank difference as the main factor.** Rejected. It is wrong when
  teams have played a different number of games and for multi-group tables.
  Points per game covers the same signal.
- **ALT-004: Poisson goals model.** Better calibrated, but it needs goals for
  and against, which `TeamStanding` does not carry (only the difference).
  Consider it for v2 if `intGoalsFor`/`intGoalsAgainst` are parsed.
- **ALT-005: Prefetch predictions for all upcoming fixtures.** Not needed.
  Both inputs are already cached, so building on long press is instant.
- **ALT-006: Counts only, ignore the order (plan v1.1).** Rejected. It treats
  a rising team (WWWLL, newest first) and a falling team (LLWWW) the same.
  It stays as the fallback when the order is unknown.
- **ALT-007: A separate "momentum" or streak bonus on top of form.**
  Rejected. It counts the same matches twice and overrates short streaks.
  Gentle recency weights express the form curve once.

## 7. Risks

- **RISK-001**: On the free key, form comes from `strForm` only. If the API
  leaves it empty for some leagues, the result is `tableOnly`. This is
  mitigated by the completeness note.
- **RISK-002**: The constants are heuristic. Mitigated by the disclaimer, the
  versioned weights and optional TASK-024.
- **RISK-003**: A long press can be hard to discover. Mitigated by the
  semantics hint and the README. A one-time snackbar hint is possible later.
- **RISK-004**: Standings may be up to 6 h old after a match day. A
  "Based on the table as of <cache time>" note would need
  `StandingsRepository` to return the cache entry time with the table.
  **Dropped from v1**: the sheet shows no table-as-of line, so no entry time
  is returned. Revisit if the age of the table needs to be visible.
- **RISK-006**: A wrong `standingsFormOrder` reverses the form curve, so a
  falling team looks like a rising one. Mitigated by TASK-019 (evidence
  before setting the constant), a pinned test, and `unknown` as the safe
  default.
- **RISK-005**: Cup or cross-league fixtures in the list: a team is not found
  → "Not enough data" (REQ-007).

## 8. Open decisions (with defaults)

1. Show percentages in v1? **Default: yes**, with the "estimate" label and
   disclaimer.
2. Is `strForm` enough for "last five" on the free key? **Default: yes.** It
   is recency-weighted once TASK-019 confirms the order, and counts only
   until then. The source is shown in the reasons.
3. Recency weights `[1.0, 0.9, 0.8, 0.7, 0.6]`? **Default: yes.** Gentle on
   purpose. Tune with TASK-024.
4. Draw verdict threshold `|pHome − pAway| < 0.10`? **Default: yes.** Tune it
   after TASK-024.
5. AI prose in v1? **Decided: yes.** Phase 5 (TASK-020 to TASK-023) is in
   scope. The deterministic text stays the fallback (CON-001). TASK-024 stays
   optional.

## 9. Relevant files

| File | Relevance |
|------|-----------|
| `lib/features/fixtures/widgets/fixture_tile.dart` | Add `onLongPress`. |
| `lib/features/fixtures/fixtures_view.dart` | Wire the long press for eligible fixtures. |
| `lib/features/team/team_detail_screen.dart` | Wire the long press; move form logic to `team_form.dart`. |
| `lib/features/reminders/match_reminder.dart` | `canRemind` is the eligibility rule. |
| `lib/features/fixtures/fixtures_repository.dart` | Shared season-events cache; expose `getSeasonEvents`. |
| `lib/features/standings/standings_repository.dart` | Cached table (6 h). |
| `lib/features/standings/standings_providers.dart` | `selectedLeagueProvider`, `seasonProvider`. |
| `lib/models/team_standing.dart` | Rank, points, goal difference, played, `form`. |
| `lib/models/fixture.dart` | `resultFor`, `isFinished`, `isLive`, `postponed`. |
| `lib/core/api/football_api_client.dart` | Free and Premium limits; rate limit. |
| `lib/features/ai/ai_service.dart`, `ai_providers.dart` | AI abstraction (Phase 5). |
| `lib/features/recap/recap_builder.dart` | Pattern for timeout, validation and fallback (Phase 5). |
| `lib/features/recap/recap_sheet.dart`, `reminders/reminder_sheet.dart` | Bottom-sheet conventions. |
| `test/features/fixtures/fixtures_view_scorers_test.dart` | Widget-test pattern with provider overrides. |
| `README.md` | Gesture documentation. |
