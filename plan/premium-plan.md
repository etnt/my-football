# My Football — Premium Implementation Plan

Plan for upgrading the app from TheSportsDB's **free** test key (`123`) to a
**Premium** key ($9/mo), and the functionality that unlocks.

Status: proposed. This document is the source of truth for the Premium work; tick
the checklists as milestones land.

---

## 1. Why go Premium

The app currently runs on the shared free key. The free key keeps the core UI
working but hard‑caps several endpoints server‑side, which produces two visible
problems today:

- **League table shows only 5 rows** (`lookuptable` free limit = 5).
- **Matches tab shows only the first ~15 events of a season** (`eventsseason`
  free limit = 15), and per‑team fixtures are effectively empty.

Premium lifts these caps, adds **livescores** and **video highlights**, and
enables the modern **v2 API**. Nothing about the free experience needs to change —
Premium features light up only when a valid key is stored.

---

## 2. Free vs Premium limits (verified from the docs)

| Method (v1) | Endpoint | Free | Premium | Feature it powers |
|---|---|---:|---:|---|
| League Table | `lookuptable.php` | 5 | 100 | Full 20‑team standings |
| Season Schedule | `eventsseason.php` | 15 | 3000 | Whole‑season fixtures |
| League Prev/Next | `eventspastleague.php` / `eventsnextleague.php` | 1 | 20 | Recent results / upcoming |
| Team Prev/Next | `eventslast.php` / `eventsnext.php` | 1 (home only) | 10 (home+away) | Per‑team schedule |
| Team Squad | `lookup_all_players.php` | 10 | 3000 | Squad + player profiles |
| Search teams/players/events | `search*.php` | 1 (only "Arsenal") | 10–100 | Working search |
| Video Highlights | `eventshighlights.php` | 2 | 50 | YouTube highlight links |
| Team Equipment (kits) | `lookupequipment.php` | 2 | 100 | Kit images |
| **Rate limit** | — | 30/min | 100/min | Smoother refresh |

**v2 API (Premium only):**
- Base URL `https://www.thesportsdb.com/api/v2/json`
- Auth header `X-API-KEY: <premium key>` (not key‑in‑path)
- Standard HTTP status codes
- Adds **Livescores** (`/livescore/{sport|idLeague|all}`) — not available in v1 at all
- Cleaner **Schedule** (`/schedule/next|previous/league/{id}`, team variants)

Timezone for all endpoints: **UTC**.

---

## 3. Authentication model

The app already stores an optional key in secure storage
(`thesportsdb_api_key`) and the client falls back to `123` when unset. We treat
"a non‑empty stored key" as **Premium mode**.

| Mode | Trigger | v1 auth | v2 auth |
|---|---|---|---|
| Free | no stored key | path `/123/…` | not available |
| Premium | stored key present | path `/<key>/…` | header `X-API-KEY: <key>` |

Key insight: **v1 limits are enforced server‑side by the key**, so simply putting
the Premium key in the path returns full data with **no client changes** to the
existing v1 calls. The new code is only for (a) v2 livescores/schedule and
(b) new screens.

---

## 4. Architecture changes

```
lib/core/api/
  football_api_client.dart     # existing v1 client (unchanged auth logic)
  sportsdb_v2_client.dart      # NEW: v2 client, header auth, HTTP-status errors
  api_exception.dart

lib/providers/
  app_providers.dart           # + isPremiumProvider (derived from apiKeyProvider)

lib/models/
  fixture.dart                 # reused for v2 events (map v2 field names)
  team_standing.dart           # unchanged (v1 lookuptable)
  player.dart                  # NEW: squad/player profile
  live_event.dart              # NEW (or reuse Fixture + isLive)
```

- **`isPremiumProvider`** — `bool` derived from `apiKeyProvider` (non‑empty ⇒ true).
  Drives feature flags in the UI (show/hide Livescores tab, search, highlights).
- **`SportsDbV2Client`** — thin dio client, base `…/api/v2/json`, `X-API-KEY`
  header, maps non‑2xx to `ApiException`. Only constructed when a key exists.
- Repositories gain a premium branch: when premium, prefer the richer endpoint
  (e.g. `eventslast`/`eventsnext` for a team) and drop the free‑tier fallbacks.

---

## 5. Feature scope & phased milestones

Each phase is independently shippable. Phase 1 is the highest value / lowest
effort and directly fixes the current complaints.

### Phase 0 — Premium plumbing
- [ ] Add `isPremiumProvider` (derived).
- [ ] Settings: "Validate key" button → make a cheap authenticated call
      (`lookuptable` for EPL) and show **Premium active** / **Invalid key**.
- [ ] Settings copy: explain free vs premium, link to the pricing page.
- [ ] Remove/replace the "Data by TheSportsDB / limited on free key" note with a
      dynamic note that only appears in free mode.

### Phase 1 — Full standings & full fixtures (data unlock)
- [ ] Confirm `lookuptable` returns the full table with a premium key (20 rows).
- [ ] Standings UI: remove any implicit 5‑row assumptions; verify scrolling.
- [ ] Fixtures: with premium, `eventsseason` returns the whole season — group the
      Matches list by round/date and keep results/upcoming split.
- [ ] Add an in‑app banner in **free** mode only: "Showing a limited preview —
      go Premium for the full table and fixtures."

### Phase 2 — Real team detail
- [ ] Team repository: in premium mode use `eventslast` (last 10) + `eventsnext`
      (next 10), which include **home and away** matches, instead of filtering the
      capped season list.
- [ ] Team detail: recent form from the last‑10, upcoming fixtures from the next‑10.
- [ ] Keep the free‑mode path (filter season events) as a graceful fallback.

### Phase 3 — Livescores (v2)
- [ ] `SportsDbV2Client.getLiveScores(leagueId)` → `/livescore/{idLeague}`.
- [ ] New **Live** section/tab (visible only in premium mode).
- [ ] Poll on a timer (e.g. every 30–60s) while the screen is visible; stop when
      backgrounded. Budget well under 100 req/min.
- [ ] Live badge + minute on match tiles; auto‑update scores.

### Phase 4 — Squad & player profiles
- [ ] `getSquad(teamId)` via `lookup_all_players` (premium 3000).
- [ ] `Player` model (name, position, nationality, photo, DOB).
- [ ] Squad list on the team detail screen → player profile screen.

### Phase 5 — Search
- [ ] Search bar for teams / players / events (premium raises the 1‑result cap).
- [ ] Debounced query; results route to team/player detail.

### Phase 6 — Highlights & polish
- [ ] `eventshighlights` links on finished matches (open YouTube).
- [ ] Optional: team kit images via `lookupequipment`.
- [ ] Optional: migrate remaining schedule calls to v2 for consistency.

---

## 6. Data model / mapping notes

- **v1 events** already map to `Fixture` (done). **v2 events** use similar field
  names but a cleaner shape — add a `Fixture.fromV2Json` factory rather than a new
  model, so the UI stays unchanged.
- **Livescores** can reuse `Fixture` with `isLive == true` plus a live minute; add
  a nullable `progress`/`minute` field if v2 provides it.
- **Player** is a new model (Phase 4).

---

## 7. UX & settings

- Settings screen becomes the Premium control center:
  - Enter/paste key → **Validate** → status chip (Free / Premium active / Invalid).
  - "Use free key" button reverts to `123`.
  - Short explainer + pricing link.
- Feature gating: Live tab, Search, Highlights, and the full‑season grouping appear
  only when `isPremium == true`. In free mode the app looks exactly as it does now,
  plus a subtle upgrade banner.

---

## 8. Rate‑limit & caching strategy (premium)

- Premium = 100 req/min. Livescore polling is the only high‑frequency caller;
  cap it to one league at a time and a sensible interval.
- Keep existing TTL caches (standings 6h, season events 30m). Livescores are **not**
  cached (real‑time), but are only fetched while the Live view is on screen.
- Keep the 429 handling already in the client.

---

## 9. Testing

- **Unit:** v2 client (header auth, HTTP‑status error mapping), `Fixture.fromV2Json`,
  `Player.fromJson`, premium‑mode repository branches (mock adapter, no network).
- **Provider:** `isPremiumProvider` toggles correctly with the stored key.
- **Widget:** Live/Search/Highlights hidden in free mode, shown in premium mode.
- **Manual (needs a real key):** validate key, full 20‑row table, whole‑season
  fixtures, team home+away schedule, live score updates during a match window.

---

## 10. Rollout

1. Land Phase 0 + Phase 1 (fixes the visible free‑tier limits for anyone with a key).
2. Ship Phases 2–6 incrementally, each behind the premium flag.
3. Never commit a real Premium key; it lives only in on‑device secure storage.

---

## 11. Open questions

- [ ] Confirm the exact v2 JSON field names for schedule & livescore (grab a sample
      once a key is available) to finalise `fromV2Json`.
- [ ] Decide whether Live is a new bottom‑nav tab or a section inside Matches.
- [ ] Confirm which leagues expose livescores for our four target leagues.
