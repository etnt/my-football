import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/league.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart' show selectedLeagueProvider;
import 'news_item.dart';

final newsProvider =
    AsyncNotifierProvider.autoDispose<NewsController, List<NewsItem>>(
      NewsController.new,
    );

/// Scope key for transient refresh status. A league, key, or age change hides
/// the previous scope's error and in-flight state immediately.
final newsRefreshScopeProvider = Provider<String>((ref) {
  final league = ref.watch(selectedLeagueProvider);
  final apiKey = ref.watch(newsApiKeyProvider).valueOrNull?.trim();
  final keyGeneration = ref.watch(newsApiKeyGenerationProvider);
  final maxAgeDays = ref.watch(newsMaxAgeDaysProvider);
  return '${league.id}:${apiKey ?? ''}:$keyGeneration:$maxAgeDays';
});

class NewsRefreshStatus {
  const NewsRefreshStatus({
    required this.scope,
    this.error,
    this.inFlight = false,
    this.requestToken,
  });

  final String scope;
  final String? error;
  final bool inFlight;
  final Object? requestToken;
}

final newsRefreshStatusProvider = StateProvider.autoDispose<NewsRefreshStatus?>(
  (ref) => null,
);

/// Error from the most recent explicit refresh in the current league/key.
final newsRefreshErrorProvider = Provider.autoDispose<String?>((ref) {
  final scope = ref.watch(newsRefreshScopeProvider);
  final status = ref.watch(newsRefreshStatusProvider);
  return status?.scope == scope ? status?.error : null;
});

/// True while the current league/key refresh is in progress.
final newsRefreshInFlightProvider = Provider.autoDispose<bool>((ref) {
  final scope = ref.watch(newsRefreshScopeProvider);
  final status = ref.watch(newsRefreshStatusProvider);
  return status?.scope == scope && (status?.inFlight ?? false);
});

/// True until a News API key is available.
final newsNeedsKeyProvider = Provider<bool>((ref) {
  return (ref.watch(newsApiKeyProvider).valueOrNull ?? '').trim().isEmpty;
});

class NewsController extends AutoDisposeAsyncNotifier<List<NewsItem>> {
  String? _scope;
  int _scopeGeneration = 0;
  bool _disposed = false;

  @override
  Future<List<NewsItem>> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final League league = ref.watch(selectedLeagueProvider);
    // Loading stored headlines never makes a network request.
    final scope = ref.watch(newsRefreshScopeProvider);
    final maxAgeDays = ref.watch(newsMaxAgeDaysProvider);
    if (_scope != scope) {
      _scope = scope;
      _scopeGeneration++;
    }
    return ref
        .watch(newsRepositoryProvider)
        .load(league.id, maxAgeDays: maxAgeDays);
  }

  Future<void> refresh() async {
    final apiKey = ref.read(newsApiKeyProvider).valueOrNull?.trim();
    if (apiKey == null || apiKey.isEmpty) return;
    if (ref.read(newsRefreshInFlightProvider)) return;
    final league = ref.read(selectedLeagueProvider);
    final maxAge = ref.read(newsMaxAgeDaysProvider);
    final repository = ref.read(newsRepositoryProvider);
    final previousItems = state.valueOrNull ?? const <NewsItem>[];
    final generation = _scopeGeneration;
    final scope = ref.read(newsRefreshScopeProvider);
    final requestToken = Object();
    bool isCurrent() =>
        !_disposed &&
        generation == _scopeGeneration &&
        ref.read(newsRefreshScopeProvider) == scope &&
        ref.read(selectedLeagueProvider).id == league.id &&
        ref.read(newsApiKeyProvider).valueOrNull?.trim() == apiKey;

    ref.read(newsRefreshStatusProvider.notifier).state = NewsRefreshStatus(
      scope: scope,
      inFlight: true,
      requestToken: requestToken,
    );
    try {
      final items = await repository.refresh(
        league: league,
        apiKey: apiKey,
        maxAgeDays: maxAge,
        isCurrent: isCurrent,
      );
      if (isCurrent()) state = AsyncData(items);
    } catch (error) {
      if (!isCurrent()) return;
      // A refresh can start while the initial local load is still pending (or
      // after it failed), so reload persisted headlines rather than replacing
      // them with an empty list captured from the prior state.
      List<NewsItem> cachedItems;
      try {
        cachedItems = await repository.load(league.id, maxAgeDays: maxAge);
      } catch (_) {
        cachedItems = previousItems;
      }
      if (!isCurrent()) return;
      state = AsyncData(cachedItems);
      ref.read(newsRefreshStatusProvider.notifier).state = NewsRefreshStatus(
        scope: scope,
        error: error.toString(),
        inFlight: true,
        requestToken: requestToken,
      );
    } finally {
      // The request may be stale for data, but it still owns its matching
      // in-flight status. Clear only that status so an older request cannot
      // clear a newer refresh in the same scope (for example A → B → A).
      if (!_disposed) {
        final status = ref.read(newsRefreshStatusProvider);
        if (status?.requestToken == requestToken) {
          ref
              .read(newsRefreshStatusProvider.notifier)
              .state = NewsRefreshStatus(
            scope: scope,
            error: status?.error,
            requestToken: requestToken,
          );
        }
      }
    }
  }
}
