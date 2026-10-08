---
goal: Show refreshable league-scoped football headlines in the News tab
version: 1.0
date_created: 2026-09-02
owner: my-football maintainers
status: 'In progress'
tags: [feature, news, gnews, settings]
---

# Introduction

This plan adds a **News** tab for headlines about the currently selected
league. The app queries GNews only when the user refreshes the tab. It stores
cleaned headline fragments on-device, filters them by a configurable age, and
opens original articles in the in-app browser. A user supplies their own GNews
API key in Settings. News is not premium-gated.

## 1. Requirements & Constraints

- **REQ-001**: The News tab shows headlines queried with the selected league's
  name and the user's GNews API key.
- **REQ-002**: Opening or switching back to News reads saved headlines only;
  network requests occur only after a user refresh.
- **REQ-003**: Headlines are stored per league as cleaned fragments: title,
  description, source, URL and publication timestamp.
- **REQ-004**: Settings offers a maximum headline age of 1, 3 or 7 days; the
  default is 1 day. Refresh filtering and stored-data pruning use this value.
- **REQ-005**: A collapsed headline shows source, relative publication time and
  title. Expanding it shows its description and a button to read the full story.
- **REQ-006**: Article links open using `LaunchMode.inAppBrowserView`.
- **REQ-007**: Without a News API key, the tab shows a Settings call to action.
- **REQ-008**: Show “Powered by GNews” attribution in the News view.
- **SEC-001**: The user's GNews key is kept on-device in the `news_api_key`
  SharedPreferences entry. It is not sent anywhere except GNews API requests.
- **SEC-002**: GNews article text is stripped of residual HTML tags and entities
  before it is stored or displayed. Article links must use HTTPS.
- **CON-001**: GNews is selected over RSS or another sports API because its
  search endpoint works with any followed league name. Users must supply their
  own free-tier GNews key. No RSS fallback is included.
- **CON-002**: No package is added. `url_launcher` is already present and its
  in-app browser mode uses Custom Tabs on Android and SFSafariViewController on
  iOS. Android is the manual verification target; iOS has not been verified.
- **CON-003**: News has its own `NewsStore`; it does not use `CacheStore` or its
  premium/free API cache prefixes. Changing or clearing the GNews key clears
  all `news_items_` preferences.
- **CON-004**: GNews rate limits or quota errors are shown to the user. The app
  does not automatically retry a failed refresh.
- **GUD-001**: News code lives in `lib/features/news/`, following the feature
  folder convention and the `MatchReminder`/`ReminderStore` pairing.
- **GUD-002**: Tests mirror source paths under `test/features/news/`.
- **PAT-001**: The store follows `ReminderStore`; provider wiring uses
  `sharedPreferencesProvider` and Riverpod patterns in the app.
- **PAT-002**: The API client is injectable and follows the thin Dio client
  pattern used by `FootballApiClient`; refresh persistence is owned by a
  `NewsRepository`.

## 2. Implementation Steps

### Implementation Phase 1 — Model, client, store and repository

- **GOAL-001**: Fetch, clean and persist league news on explicit refresh.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add the feature-local `NewsItem` model and JSON serialization. | ✅ | 2026-09-02 |
| TASK-002 | Add the injectable GNews search client, HTML/entity cleanup and typed API errors. | ✅ | 2026-09-02 |
| TASK-003 | Add per-league `NewsStore` load, wholesale replace, prune and clear-all operations. | ✅ | 2026-09-02 |
| TASK-004 | Add `NewsRepository.refresh` to fetch, filter, prune and persist, without fetch-on-open behavior. | ✅ | 2026-09-02 |

### Implementation Phase 2 — Providers and Settings

- **GOAL-002**: Store the user's key and age preference and make them available to News.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-005 | Add the SharedPreferences-backed GNews key notifier and clear saved news when the key changes. | ✅ | 2026-09-02 |
| TASK-006 | Add API client, store, repository and max-age providers (default 1 day). | ✅ | 2026-09-02 |
| TASK-007 | Add the masked GNews key editor, validate/save/clear actions and 1/3/7-day max-age dropdown in Settings. | ✅ | 2026-09-02 |

### Implementation Phase 3 — UI and navigation

- **GOAL-003**: Present stored league news and offer deliberate refresh and article browsing.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-008 | Add stored-first `NewsController` and key-required state. | ✅ | 2026-09-02 |
| TASK-009 | Add the refreshable accordion list, empty/error states, attribution and in-app links. | ✅ | 2026-09-02 |
| TASK-010 | Add News after Matches and before Premium-only Stats/Live in the bottom navigation. | ✅ | 2026-09-02 |

### Implementation Phase 4 — Tests and documentation

- **GOAL-004**: Cover key behavior and document how to use the feature.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-011 | Test store round-trip, corruption, pruning and cache clearing. | ✅ | 2026-09-02 |
| TASK-012 | Test GNews mapping, sanitization, API errors, refresh filtering and persistence. | ✅ | 2026-09-02 |
| TASK-013 | Test News collapsed/expanded rows and empty states. | ✅ | 2026-09-02 |
| TASK-014 | Document News in README and DEVELOPERS guides and run validation. | ✅ | 2026-09-02 |

## 3. Alternatives

- **ALT-001**: Curated RSS feed list. Rejected because it cannot reliably cover
  arbitrary followed leagues; GNews search supports a generic league-name query.
- **ALT-002**: A separate news service requiring a shared app key. Rejected:
  users provide their own GNews key, and News therefore does not need Premium
  gating or a backend secret.
- **ALT-003**: External browser or a new browser package. Rejected because
  `url_launcher` already provides `LaunchMode.inAppBrowserView`.

## 4. Dependencies

- **DEP-001**: `dio` — already present; HTTP transport for GNews.
- **DEP-002**: `shared_preferences` — already present; stores the key, age
  preference and per-league news fragments.
- **DEP-003**: `flutter_riverpod` — already present; providers and async UI state.
- **DEP-004**: `url_launcher` — already present; opens article URLs in the
  platform in-app browser.
- **DEP-005**: No runtime package changes are required.

## 5. Files

- `lib/features/news/news_item.dart` — news model and safe text cleanup.
- `lib/features/news/news_api_client.dart` — GNews Dio client and errors.
- `lib/features/news/news_store.dart` — league-specific SharedPreferences data.
- `lib/features/news/news_repository.dart` — refresh/filter/persist behavior.
- `lib/features/news/news_providers.dart` — stored-first Riverpod controller.
- `lib/features/news/news_view.dart` and `time_ago.dart` — tab UI and timestamps.
- `lib/providers/app_providers.dart` — key, client, store and max-age providers.
- `lib/features/settings/settings_screen.dart` — key and age controls.
- `lib/features/home/home_shell.dart` — bottom navigation destination.
- `test/features/news/` — API, repository, store and widget tests.
- `README.md`, `DEVELOPERS.md` — user and developer feature notes.

## 6. Testing

- **TEST-001**: Store round-trip, malformed payload, age prune and key-change
  invalidation tests.
- **TEST-002**: GNews payload decode, text sanitization and typed 4xx error tests.
- **TEST-003**: Repository max-age filtering, persistence and error propagation.
- **TEST-004**: Widget tests for collapsed/expanded rows, missing-key and
  no-cached-headline states.
- **TEST-005**: Run `flutter analyze` and `flutter test` for regression coverage.
- **TEST-006**: Manual Android check of Settings key validation, refresh, league
  separation, age filtering and in-app article browser. iOS is unverified.

## 7. Risks & Assumptions

- **RISK-001**: GNews free-tier quotas can be exhausted or limited. Show its API
  error and never retry automatically.
- **RISK-002**: League-name search can return loosely related stories. The v1
  query is the league name alone, as decided for generic coverage; future query
  tuning can be evaluated without changing persistence.
- **RISK-003**: The key is stored as a plain SharedPreferences value rather than
  secure storage. This is an intentional v1 decision for a user-owned free key;
  it stays on-device and is removed with the News cache when changed.
- **RISK-004**: GNews attribution requirements may change. The UI includes
  “Powered by GNews” as a safe default; review current GNews terms before release.
- **RISK-005**: In-app browser behavior is not manually verified on iOS.
- **ASSUMPTION-001**: The selected league's display name is a useful English
  query. Search language is set to English.
- **ASSUMPTION-002**: A refresh replaces the current league's saved list with
  the filtered response; old items are not merged into new results.
