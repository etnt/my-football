import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/league.dart';
import '../../models/team_standing.dart';
import '../../providers/app_providers.dart';
import 'standings_repository.dart';

final standingsRepositoryProvider = Provider<StandingsRepository>((ref) {
  return StandingsRepository(
    client: ref.watch(footballApiClientProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Currently selected league.
final selectedLeagueProvider =
    StateProvider<League>((ref) => League.premierLeague);

/// Selected season (starting year). `2025` (2025-2026) is a good default with a
/// complete table; the in-progress current season may be sparse.
final seasonProvider = StateProvider<int>((ref) => 2025);

/// The standings for the selected league/season.
final standingsProvider = AsyncNotifierProvider.autoDispose<StandingsNotifier,
    List<TeamStanding>>(StandingsNotifier.new);

class StandingsNotifier
    extends AutoDisposeAsyncNotifier<List<TeamStanding>> {
  @override
  Future<List<TeamStanding>> build() {
    final league = ref.watch(selectedLeagueProvider);
    final season = ref.watch(seasonProvider);
    return ref
        .watch(standingsRepositoryProvider)
        .getStandings(league: league, season: season);
  }

  /// Force a network refresh (used by pull-to-refresh), bypassing the cache.
  Future<void> refresh() async {
    final league = ref.read(selectedLeagueProvider);
    final season = ref.read(seasonProvider);
    final repo = ref.read(standingsRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repo.getStandings(
        league: league,
        season: season,
        forceRefresh: true,
      ),
    );
  }
}
