# My Football — Build Plan

A simple, extensible Flutter mobile app for browsing football data from
[API-Football (v3)](https://www.api-football.com/). The first milestone shows the
league table (standings) for the four major leagues, lets the user enter their API
key, and tracks how many API requests remain on the Free plan.

---

## 1. Goals & scope

### MVP (Milestone 1)
- Enter and securely store the API key.
- Pick one of four leagues: Premier League, La Liga, Serie A, Bundesliga.
- Display the current standings table (rank, team, played, W/D/L, GD, points).
- Show remaining API requests for the day (Free plan = 100/day).
- Cache results locally so we don't burn through the quota on every screen open.

### Explicitly out of scope for MVP (but designed to add later)
- Fixtures / results / live scores
- Team & player details
- Multiple seasons, search, favourites
- Push notifications
- Sharing with friends / accounts

The architecture below keeps these easy to add.

---

## 2. Understanding the API (Free plan)

You registered directly on api-football.com, so use the **direct API-Sports host**
(not the RapidAPI host).

- **Base URL:** `https://v3.football.api-sports.io`
- **Auth header:** `x-apisports-key: <YOUR_KEY>`
- **Format:** JSON. Every response has this envelope:
  ```jsonc
  {
    "get": "standings",
    "parameters": { "league": "39", "season": "2025" },
    "errors": [],        // populated on error (e.g. wrong key, quota exceeded)
    "results": 1,
    "paging": { "current": 1, "total": 1 },
    "response": [ /* ... payload ... */ ]
  }
  ```

### Rate limiting (important on the Free plan)
- **Daily limit:** 100 requests/day.
- **Burst limit:** ~10 requests/minute.
- Every HTTP response includes headers we can read to show remaining calls:
  - `x-ratelimit-requests-limit` — daily limit (e.g. `100`)
  - `x-ratelimit-requests-remaining` — remaining today
  - `X-RateLimit-Limit` / `X-RateLimit-Remaining` — per-minute window
- There is also a dedicated endpoint that reports account/quota status:
  - `GET /status` → `response.requests.current`, `response.requests.limit_day`,
    `response.subscription.plan`, `response.subscription.end`.

> **Strategy:** Update the "remaining requests" counter from the response headers of
> *every* call (free — no extra request), and offer a manual "Refresh account status"
> button that calls `/status` when the user wants an authoritative number.

### Standings endpoint
```
GET /standings?league={leagueId}&season={year}
```
- **League IDs:** Premier League `39`, La Liga `140`, Serie A `135`, Bundesliga `78`.
- **season** is the starting year of the campaign (e.g. `2025` for 2025/26).
- Payload shape:
  ```
  response[0].league.standings  // a List<List<TeamStanding>>
                                 // (outer list = groups; leagues above have 1 group)
  ```
  Each team standing has: `rank`, `team {id, name, logo}`, `points`, `goalsDiff`,
  `all {played, win, draw, lose, goals {for, against}}`, `form`.

> **Note on season coverage:** The Free plan restricts which seasons are available.
> Confirm the allowed season for your account (check `/status` or the dashboard) and
> make the season configurable rather than hard-coded.

---

## 3. Tech choices

| Concern            | Choice                     | Why |
|--------------------|----------------------------|-----|
| Framework          | Flutter (stable channel)   | Requested; single codebase for iOS/Android |
| HTTP               | `dio`                      | Interceptors make it easy to capture rate-limit headers centrally |
| State management   | `flutter_riverpod`         | Simple, testable, scales as features grow |
| Secure key storage | `flutter_secure_storage`   | Keeps the API key out of plaintext prefs |
| Local cache        | `shared_preferences` (MVP) | Cache JSON + timestamp; swap for Hive later if needed |
| JSON models        | Hand-written (MVP)         | Few models; add `json_serializable` if they grow |

Keep dependencies minimal at first; each can be revisited.

---

## 4. Proposed project structure

```
lib/
  main.dart
  app.dart                       # MaterialApp, routing, theme
  core/
    api/
      football_api_client.dart   # dio setup, base URL, key header, error mapping
      rate_limit.dart            # RateLimitInfo model + parser for headers
      api_exception.dart
    storage/
      secure_key_store.dart      # save/read/clear API key
      cache_store.dart           # generic "json + timestamp" cache with TTL
  models/
    league.dart                  # enum/const: id, name, season for the 4 leagues
    team_standing.dart
    account_status.dart
  features/
    settings/
      settings_screen.dart       # enter/update/clear key, show account status
    standings/
      standings_providers.dart   # Riverpod providers (async standings, selected league)
      standings_screen.dart      # league picker + table
      widgets/standings_table.dart
  shared/
    widgets/                     # loading, error, empty states
providers/
  app_providers.dart             # rate-limit state provider (global)
```

---

## 5. Key design decisions

### 5.1 API key handling
- Store with `flutter_secure_storage`; never bundle it in the app or commit it.
- On first launch (or when missing), route the user to **Settings** to enter the key.
- Validate a newly entered key by calling `/status`; show plan + daily limit on success.
- The repo's `API-KEY.txt` is for your convenience during development only. A
  `.gitignore` has been added so it is **not committed**. Do not hard-code the key.

### 5.2 Rate-limit tracking (the "requests remaining" feature)
- A `dio` interceptor reads the rate-limit headers on every response and updates a
  global `RateLimitInfo` (remaining today, daily limit, per-minute remaining, timestamp).
- Display it persistently (e.g. an app-bar badge like `87/100`).
- Optionally warn/block near zero to avoid a hard quota error.

### 5.3 Caching to protect the quota
- Cache standings per `(league, season)` with a TTL (e.g. 6–12 hours).
- Screen open → serve fresh cache if within TTL; otherwise fetch and update cache.
- Add pull-to-refresh for a manual, deliberate fetch.
- This keeps normal usage well under 100 requests/day.

### 5.4 Error handling
- Map common cases to friendly messages:
  - Missing/invalid key → prompt to fix it in Settings.
  - Quota exceeded (`errors` populated / 429) → show remaining resets, offer cached data.
  - Network offline → serve last cache with a "stale" indicator.

---

## 6. Milestones / task breakdown

### Milestone 0 — Project setup
- [ ] `flutter create` the app; set app name/bundle id.
- [ ] Add dependencies: `dio`, `flutter_riverpod`, `flutter_secure_storage`, `shared_preferences`.
- [ ] Wire up `ProviderScope`, base theme, and routing skeleton.

### Milestone 1 — API key + standings (MVP)
- [ ] `secure_key_store` + Settings screen to enter/clear the key.
- [ ] `football_api_client` with auth header and error envelope handling.
- [ ] Rate-limit interceptor + global `RateLimitInfo` + app-bar badge.
- [ ] `/status` call to validate key and show plan/quota.
- [ ] Standings models + `/standings` fetch.
- [ ] League picker (4 leagues) + standings table UI.
- [ ] Cache with TTL + pull-to-refresh.
- [ ] Loading / error / empty states.

### Milestone 2+ — Extensions (pick as desired)
- [ ] Fixtures & results per league (`/fixtures`).
- [ ] Live scores.
- [ ] Team detail screen (form, next matches).
- [ ] Season selector; favourites; light/dark theme polish.

---

## 7. Manual test checklist (MVP)
- Enter a valid key → account status shows plan + daily limit.
- Enter an invalid key → clear error, not a crash.
- Switch between all four leagues → correct tables load.
- Reopen a league within TTL → no new API request (verify counter unchanged).
- Pull-to-refresh → counter decreases by one.
- Airplane mode → last cached table shown with a "stale" note.

---

## 8. Security reminders
- **Never commit `API-KEY.txt`** (now covered by `.gitignore`).
- If this repo was ever pushed with the key, **rotate the key** in the dashboard.
- Keep the key in secure storage on-device, not in source or shared preferences.

---

## 9. Next step
When you're happy with this plan, the first coding step is **Milestone 0**: scaffold
the Flutter project and add the dependencies. Say the word and I'll set it up.
