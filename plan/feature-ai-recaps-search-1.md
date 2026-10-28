---
goal: Add on-device AI match recaps and natural-language search, with deterministic fallbacks
version: 1.0
date_created: 2026-10-24
owner: my-football maintainers
status: 'Proposed'
tags: [feature, ai, gemini-nano, fixtures, search]
---

# Introduction

This plan adds two features that use a small on-device model (Gemini Nano on
supported Android phones):

1. **Match recaps:** a short written summary of a finished match.
2. **Natural-language search:** answers to questions such as "Who scored the
   most goals for Arsenal in the last 5 games?"

The model never computes facts. Dart code builds every fact and every result.
The model only writes prose (recaps) or turns a question into a structured
query (search). The app validates both before showing them. Every feature has a
deterministic fallback, so the app works on devices without Gemini Nano.

**Status note:** the Gemini Nano / ML Kit GenAI details in section 5 are
assumptions. Verify them against the current Android documentation during the
spike (Milestone 1) before committing to the design.

---

# 1. Goals and non-goals

## Goals
- Show a recap for any finished fixture, with or without a model.
- Answer a bounded set of statistical questions from cached data.
- Keep all data on the device. Nothing is sent to a third-party AI service.
- Never show numbers or names that the app cannot trace to its own data.

## Non-goals
- Open-ended chat or general football knowledge.
- Recaps for matches in progress (decision pending, see section 9).
- iOS model support (Gemini Nano is Android-only; iOS uses the fallbacks).
- Training or fine-tuning any model.

---

# 2. Current data the features build on

| Need | Existing source | Notes |
|------|-----------------|-------|
| Teams, score, date, round, status | `Fixture` (`lib/models/fixture.dart`), `FixturesRepository` | Cached per season under `season_events_<league>_<season>` |
| Goals with minute, scorer, assist, penalty, own goal | `GoalEvent` (`lib/models/goal_event.dart`) | From the v2 timeline (Premium). May be missing on the free key |
| Cards | `CardEvent` (`lib/models/card_event.dart`) | Same timeline source |
| Standings | `StandingsRepository` | Cached under `standings_*` |
| Player and team stats | `PlayerStatsRepository`, `TeamRepository` | Cached under `stats_*`, `team_events_*` |
| Lineups | `LineupRepository` | Cached under `lineup_*` |
| Team name matching | `lib/core/text/lookup_text_normalizer.dart` | Reused for search entity resolution |
| Cache with TTL | `CacheStore` (`lib/core/storage/cache_store.dart`) | Add new key prefixes here (`recap_`, `search_`) |

Both features read only from these sources. Neither adds network calls.

---

# 3. Architecture

```
UI
 ├── Match detail: "Recap" section
 └── Search bar (Fixtures / Stats tab)
        │
        ▼
Feature layer (Dart)
 ├── RecapBuilder ──► FactSheet ──► prompt ──► validated text
 └── QueryPlanner ──► QuerySpec (JSON) ──► validator ──► QueryExecutor
        │
        ▼
AiService (interface)
 ├── GeminiNanoService     platform channel → Kotlin → ML Kit GenAI (on device)
 └── UnavailableAiService  returns "unavailable"; features use fallbacks
        │
        ▼
Existing repositories + CacheStore (the only source of facts)
```

## 3.1 Proposed files

```
lib/
  features/ai/
    ai_service.dart              # abstract interface + AiResult type
    gemini_nano_service.dart     # MethodChannel wrapper
    unavailable_ai_service.dart  # fallback
    ai_providers.dart            # Riverpod: picks implementation by isAvailable()
    prompt_templates.dart        # all prompt text in one place (versioned)
    output_validator.dart        # shared checks (numbers, names, length, JSON)
  features/recap/
    fact_sheet.dart              # FactSheet model + builder from Fixture + GoalEvent + CardEvent
    recap_builder.dart           # template recap + model rewrite + validation
    recap_sheet.dart             # UI
  features/search/
    query_spec.dart              # QuerySpec model, allowed metrics enum, JSON parse
    query_planner.dart           # question → model → QuerySpec
    query_executor.dart          # QuerySpec → results, pure Dart, no network
    search_view.dart             # UI: input, interpretation line, results
android/app/src/main/kotlin/.../
  GeminiNanoPlugin.kt            # MethodChannel "my_football/ai": isAvailable, generate
```

---

# 4. Feature A: match recaps

## 4.1 Trigger
A "Recap" section in the match detail view, shown only when the fixture
`isFinished` is true.

## 4.2 Fact sheet
`FactSheet` is built in Dart. Fields:
- Competition, round, date (local time).
- Home and away team names, final score, half-time score when available.
- Goals in order: minute, scorer, team, flags for penalty and own goal, assist.
- Cards in order: minute, player, team, card type.
- A flag saying whether event data is complete. If the timeline is missing, the
  fact sheet contains only the score.

## 4.3 Steps
1. Build the fact sheet.
2. Create the **template recap** (deterministic text, e.g. "Arsenal 2–1
   Chelsea. Goals: Saka 12', Havertz 58' (pen.). Chelsea reduced to ten after
   Caicedo's 80' red card."). Show it immediately. This is the fallback.
3. If `AiService.isAvailable()` is true, send the fact sheet with the recap
   prompt. Ask for 2–4 sentences, plain English, no new facts.
4. Validate the model output (section 6). If any check fails, keep the template.
5. Store the final text under `recap_<fixtureId>`. Finished matches do not
   change, so this entry has no TTL. Store the template and the model version
   separately so a prompt change can invalidate model-written recaps only.

## 4.4 UI
- Label model-written text "Written by on-device AI". Show a "Show facts" toggle
  that displays the fact sheet as a list.
- While the model runs, show the template with a spinner next to the label.
- If the model times out (proposed: 8 seconds), keep the template.

---

# 5. Feature B: natural-language search

## 5.1 Supported questions (first version)
A fixed set of metrics and filters. Anything else is reported as unsupported.

| Metric | Example |
|--------|---------|
| `goals_scored` (team or player) | "Most goals for Arsenal this season" |
| `goals_conceded` (team) | "Which team conceded the fewest goals?" |
| `assists` (player) | "Top assists in the league" |
| `points` (team, from standings) | "Points for Chelsea" |
| `wins`, `clean_sheets` (team) | "Wins for Liverpool at home" |

Filters: team, venue (home/away), month, last N matches, season, sort, limit.

## 5.2 Steps
1. The planner sends the question, the allowed schema, and 3–5 examples to the
   model. The model must return JSON only:
   ```json
   {"metric":"goals_scored","entity":"player","team":"Arsenal",
    "filter":{"venue":"away","month":3},"sort":"desc","limit":5}
   ```
2. The validator (section 6) checks the JSON:
   - `metric`, `entity`, `venue`, `sort` must be in fixed enums.
   - `team` must resolve to one known team using `lookup_text_normalizer`.
     If it matches several, or none, ask the user to choose.
   - `month`, `limit` (max 20), and "last N" (max 50) must be in range.
3. `QueryExecutor` runs the query in Dart against cached data. It returns
   the rows, the total, and the cache age. The model does not compute results.
4. The UI shows an **interpretation line** ("Showing: goals scored by Arsenal
   players, away matches in March") so the user can see how the question was
   read. If the user taps it, they can edit the interpretation and run the
   query again without a model call.
5. If the question does not map to a supported metric, or the JSON is invalid
   twice, show "I can't answer that yet" and list the supported examples.

## 5.3 Fallback without a model
Show a plain filter UI: metric dropdown, team picker, venue, and limit. It
produces the same `QuerySpec`, so the executor is shared.

## 5.4 Data freshness
Results show "Based on data cached at HH:mm". If the cache is older than the
normal TTL, say so.

---

# 6. Output validation (shared)

| Check | Applies to | Rule |
|-------|-----------|------|
| Numbers | Recap text | Every number in the text must appear in the fact sheet (scores, minutes, counts) |
| Names | Recap text | Every capitalised name must come from the fact sheet, team names, or the roster |
| Length | Recap text | 60–600 characters; otherwise rejected |
| Forbidden content | Recap text | No claims about injuries, transfers, or referee decisions unless present in the facts |
| JSON | Search | Must parse; unknown keys ignored, unknown values rejected |
| Enums | Search | `metric`, `entity`, `venue`, `sort` must match the allowed list exactly |
| Ranges | Search | Dates, limit, and N in range |
| Entity | Search | Team must resolve to exactly one known team |

A rejected output is logged with a reason code. No user-visible error is shown
for a model failure. The user sees the fallback.

---

# 7. Gemini Nano integration (spike)

## 7.1 Platform channel contract
- Channel: `my_football/ai`
- `isAvailable() → {available: bool, reason: String}` where reason is one of
  `ok`, `device_unsupported`, `model_downloading`, `model_not_installed`,
  `os_unsupported`.
- `generate({prompt: String, maxTokens: int, temperature: double}) → String`.
  Errors are returned as `PlatformException` with a code, never a crash.
- Calls run on a background thread in Kotlin and return to the main thread.

## 7.2 Checks to complete during the spike
- Current ML Kit GenAI / Prompt API artifact, package names, and supported
  devices (verify in the official docs).
- Whether the model must be downloaded, and how the app should react while it
  downloads.
- Minimum Android API level and the current `minSdk` in `android/app/build.gradle*`.
- Context window size and typical latency for a 300-token recap prompt on a
  supported phone.
- Behaviour when the user has disabled AI features in system settings.

## 7.3 Dart-side
`GeminiNanoService` wraps the channel. `UnavailableAiService` is used when
`isAvailable()` returns anything other than `ok`, when the platform is not
Android, or when the user has turned AI off in Settings.

---

# 8. Settings and privacy

- New Settings switch: **"On-device AI features"** (default on where supported).
  When off, all features use the fallbacks.
- No data leaves the device. No new network calls. No new API keys.
- Recaps and search results are stored only in `CacheStore`.
- The AI label is always visible on model output.

---

# 9. Open decisions

1. **Android-only model features?** Confirmed plan: yes, with the same fallbacks
   on iOS. Needs sign-off.
2. **Premium key:** without the timeline, recaps have no scorers or minutes.
   Decide whether the feature ships on the free key with score-only recaps, or
   waits for Premium.
3. **Live matches:** recaps only for finished matches (proposed), or also a
   running summary?
4. **Search scope:** current season only (proposed for v1), or every cached season?
5. **Supported device share:** if very few users have a supported phone, is
   the template recap plus the filter UI enough to ship?

---

# 10. Milestones

## Milestone 1 — Spike (about 1 week)
- [ ] Verify the ML Kit GenAI / Gemini Nano docs and supported devices (section 7.2).
- [ ] Kotlin plugin with `isAvailable` and `generate`.
- [ ] Dart `AiService`, `GeminiNanoService`, `UnavailableAiService`, provider.
- [ ] Hello-world prompt on a supported phone; record latency and reason codes.
- [ ] Unit test for `UnavailableAiService` and reason-code mapping.

## Milestone 2 — Recaps
- [ ] `FactSheet` builder with unit tests using existing fixture and goal data.
- [ ] Template recap (works with no model). Shown in match detail.
- [ ] Prompt template v1 and model rewrite with validation (section 6).
- [ ] Caching under `recap_`, with prompt version in the key.
- [ ] "Show facts" toggle and AI label.
- [ ] Timeout and fallback tests with a fake `AiService`.

## Milestone 3 — Search
- [ ] `QuerySpec` model, metric enums, JSON parsing and validation tests.
- [ ] `QueryExecutor` with unit tests on fixture data (no model).
- [ ] Filter UI fallback (no model).
- [ ] Planner prompt and examples; unsupported-question response.
- [ ] Interpretation line with edit-and-rerun.

## Milestone 4 — Evaluation and release
- [ ] Golden set of about 50 questions with expected `QuerySpec` values.
- [ ] Golden set of about 20 fact sheets with expected recap checks passing.
- [ ] Manual test on one supported and one unsupported device.
- [ ] Settings switch and privacy text reviewed.

---

# 11. Test checklist

- Finished match with full timeline → recap includes scorers, minutes, cards.
- Finished match without timeline → score-only recap, no invented scorers.
- Model output with a made-up number → rejected, template shown.
- Model output with a made-up player name → rejected, template shown.
- Search "Arsenal away goals in March" → correct executor result, interpretation line shown.
- Search with an unknown team → clarification prompt, no query run.
- Search with an unsupported metric → "can't answer yet" with examples.
- Unsupported device → no model calls, fallbacks only, no errors shown.
- AI switch off → no model calls.
- Model timeout → template or filter UI, no spinner left behind.

---

# 12. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Few devices support the model | Most users see fallbacks only | Make fallbacks good; decide whether to ship on that basis (open decision 5) |
| Timeline missing on the free key | Recaps lack scorers and minutes | Score-only recap; Premium plan (open decision 2) |
| Model invents facts | Wrong information shown | Validation layer; template fallback; AI label |
| Latency | Slow recaps | Template shown first; timeout; cache |
| ML Kit / Gemini Nano API changes | Build or runtime breakage | Isolate in one Kotlin plugin; feature flag |
| Prompt quality varies by device | Inconsistent wording | Golden set; prompt versioning in cache key |
