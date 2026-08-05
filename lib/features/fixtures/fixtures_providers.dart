import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart' show selectedLeagueProvider, seasonProvider;
import 'fixtures_repository.dart';

final fixturesRepositoryProvider = Provider<FixturesRepository>((ref) {
  return FixturesRepository(
    client: ref.watch(footballApiClientProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Results vs upcoming toggle.
final fixturesModeProvider =
    StateProvider<FixturesMode>((ref) => FixturesMode.results);

/// Fixtures for the selected league/season/mode.
final fixturesProvider =
    AsyncNotifierProvider.autoDispose<FixturesNotifier, List<Fixture>>(
  FixturesNotifier.new,
);

class FixturesNotifier extends AutoDisposeAsyncNotifier<List<Fixture>> {
  @override
  Future<List<Fixture>> build() {
    final league = ref.watch(selectedLeagueProvider);
    final season = ref.watch(seasonProvider);
    final mode = ref.watch(fixturesModeProvider);
    return ref.watch(fixturesRepositoryProvider).getFixtures(
          league: league,
          season: season,
          mode: mode,
        );
  }

  /// Force a network refresh (pull-to-refresh), bypassing the cache.
  Future<void> refresh() async {
    final league = ref.read(selectedLeagueProvider);
    final season = ref.read(seasonProvider);
    final mode = ref.read(fixturesModeProvider);
    final repo = ref.read(fixturesRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repo.getFixtures(
        league: league,
        season: season,
        mode: mode,
        forceRefresh: true,
      ),
    );
  }
}
