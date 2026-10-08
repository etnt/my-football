import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/football_api_client.dart';
import '../core/api/league_season_resolver.dart';
import '../core/api/sportsdb_v2_client.dart';
import '../features/lineups/lineup_repository.dart';
import '../features/news/news_api_client.dart';
import '../features/news/news_repository.dart';
import '../features/news/news_store.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/secure_key_store.dart';

/// Provides the initialised [SharedPreferences]. Overridden in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);

/// Changes immediately when the saved News key is edited, before cache clearing
/// finishes, so in-flight responses become stale at once.
final newsApiKeyGenerationProvider = StateProvider<int>((ref) => 0);

/// GNews key is a personal, free-tier key stored in SharedPreferences.
final newsApiKeyProvider = AsyncNotifierProvider<NewsApiKeyNotifier, String?>(
  NewsApiKeyNotifier.new,
);

class NewsApiKeyNotifier extends AsyncNotifier<String?> {
  static const _prefsKey = 'news_api_key';

  @override
  Future<String?> build() async =>
      ref.read(sharedPreferencesProvider).getString(_prefsKey);

  Future<void> setKey(String key) async {
    ref.read(newsApiKeyGenerationProvider.notifier).state++;
    final trimmed = key.trim();
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, trimmed);
    await NewsStore.clearAll(ref.read(sharedPreferencesProvider));
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    ref.read(newsApiKeyGenerationProvider.notifier).state++;
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
    await NewsStore.clearAll(ref.read(sharedPreferencesProvider));
    state = const AsyncData(null);
  }
}

/// Maximum headline age, restored from preferences on provider creation.
final newsMaxAgeDaysProvider =
    StateNotifierProvider<NewsMaxAgeDaysNotifier, int>((ref) {
      return NewsMaxAgeDaysNotifier(
        ref.read(sharedPreferencesProvider),
        ref.read(newsStoreProvider),
      );
    });

class NewsMaxAgeDaysNotifier extends StateNotifier<int> {
  NewsMaxAgeDaysNotifier(SharedPreferences prefs, NewsStore store)
    : _prefs = prefs,
      _store = store,
      super(_savedMaxAge(prefs));

  final SharedPreferences _prefs;
  final NewsStore _store;

  static int _savedMaxAge(SharedPreferences prefs) {
    final saved = prefs.getInt('news_max_age_days');
    return saved != null && [1, 3, 7].contains(saved) ? saved : 1;
  }

  Future<void> setDays(int days) async {
    if (![1, 3, 7].contains(days)) {
      throw ArgumentError.value(days, 'days', 'Must be 1, 3, or 7.');
    }
    if (days == state) return;
    state = days;
    await _prefs.setInt('news_max_age_days', days);
    await _store.pruneAllOlderThan(
      DateTime.now().toUtc().subtract(Duration(days: days)),
    );
  }
}

/// The current API key (loaded from secure storage). `null` means "not set".
final apiKeyProvider = AsyncNotifierProvider<ApiKeyNotifier, String?>(
  ApiKeyNotifier.new,
);

class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(secureKeyStoreProvider).read();

  Future<void> setKey(String key) async {
    final trimmed = key.trim();
    await ref.read(secureKeyStoreProvider).save(trimmed);
    await _clearCaches();
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(secureKeyStoreProvider).clear();
    await _clearCaches();
    state = const AsyncData(null);
  }

  /// Cached free/Premium responses must not mix, so wipe them on any key change.
  Future<void> _clearCaches() async {
    await CacheStore(ref.read(sharedPreferencesProvider)).clearAll();
  }
}

/// Per-league persisted news fragments.
final newsStoreProvider = Provider<NewsStore>((ref) {
  return NewsStore(ref.watch(sharedPreferencesProvider));
});

/// GNews client rebuilt when the configured key changes.
final newsApiClientProvider = Provider<NewsApiClient>((ref) {
  ref.watch(newsApiKeyProvider);
  final client = NewsApiClient();
  ref.onDispose(client.close);
  return client;
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(
    client: ref.watch(newsApiClientProvider),
    store: ref.watch(newsStoreProvider),
  );
});

/// Increments each time an API request is throttled (HTTP 429). The UI listens
/// to this to surface a brief "rate limit reached" notice. We can't show a
/// remaining-quota count because TheSportsDB doesn't report one, so this is a
/// reactive warning only.
final rateLimitProvider = NotifierProvider<RateLimitController, int>(
  RateLimitController.new,
);

class RateLimitController extends Notifier<int> {
  @override
  int build() => 0;

  /// Records a throttle event.
  void hit() => state = state + 1;
}

/// API client rebuilt whenever the key changes.
final footballApiClientProvider = Provider<FootballApiClient>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  final client = FootballApiClient(
    apiKey: key,
    onRateLimited: () => ref.read(rateLimitProvider.notifier).hit(),
  );
  ref.onDispose(client.close);
  return client;
});

/// Resolves the season string TheSportsDB expects per league (split years for
/// the European leagues, single calendar years for e.g. Allsvenskan).
final leagueSeasonResolverProvider = Provider<LeagueSeasonResolver>((ref) {
  return LeagueSeasonResolver(
    client: ref.watch(footballApiClientProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Fetches match line-ups with a local cache.
final lineupRepositoryProvider = Provider<LineupRepository>((ref) {
  return LineupRepository(
    client: ref.watch(footballApiClientProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// True when a (Premium) key is stored — unlocks v2 features like livescores.
final isPremiumProvider = Provider<bool>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  return (key ?? '').trim().isNotEmpty;
});

/// The v2 client, available only in Premium mode. `null` on the free key.
final sportsDbV2ClientProvider = Provider<SportsDbV2Client?>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull?.trim();
  if (key == null || key.isEmpty) return null;
  final client = SportsDbV2Client(
    apiKey: key,
    onRateLimited: () => ref.read(rateLimitProvider.notifier).hit(),
  );
  ref.onDispose(client.close);
  return client;
});
