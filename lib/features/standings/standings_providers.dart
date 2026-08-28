import 'dart:convert';

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

/// Persistence key for the user's followed leagues (a JSON-encoded list).
const _followedLeaguesKey = 'followed_leagues_v2';

/// The leagues the user has chosen to follow, persisted to [SharedPreferences].
/// These populate the league dropdown at the top of the app. Defaults to the
/// original MVP leagues on first run.
final followedLeaguesProvider =
    NotifierProvider<FollowedLeaguesNotifier, List<League>>(
        FollowedLeaguesNotifier.new);

class FollowedLeaguesNotifier extends Notifier<List<League>> {
  @override
  List<League> build() {
    final raw =
        ref.watch(sharedPreferencesProvider).getString(_followedLeaguesKey);
    if (raw == null) return League.defaults.toList();
    try {
      final leagues = (jsonDecode(raw) as List)
          .map((e) => League.fromJson(e as Map<String, dynamic>))
          .toList();
      return leagues.isEmpty ? League.defaults.toList() : leagues;
    } catch (_) {
      return League.defaults.toList();
    }
  }

  /// Whether [league] is currently followed (compared by ID).
  bool isFollowed(League league) => state.any((l) => l.id == league.id);

  /// Follows or unfollows [league]. Refuses to unfollow the last remaining
  /// league (at least one must stay followed). If the currently selected
  /// league is unfollowed, selection falls back to the first followed league.
  Future<void> toggle(League league) async {
    final current = [...state];
    final index = current.indexWhere((l) => l.id == league.id);
    if (index >= 0) {
      if (current.length == 1) return;
      current.removeAt(index);
    } else {
      current.add(league);
    }
    await ref.read(sharedPreferencesProvider).setString(
          _followedLeaguesKey,
          jsonEncode(current.map((l) => l.toJson()).toList()),
        );
    state = current;

    // Ensure the selected league is still one we follow.
    final selected = ref.read(selectedLeagueProvider);
    if (!current.any((l) => l.id == selected.id)) {
      ref.read(selectedLeagueProvider.notifier).state = current.first;
    }
  }
}

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
