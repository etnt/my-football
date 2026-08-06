import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/league.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart';
import 'player_stats.dart';
import 'player_stats_repository.dart';

/// Which leaderboard the Stats view is showing.
enum StatsBoard { scorers, assists, cards }

final statsBoardProvider = StateProvider<StatsBoard>((ref) => StatsBoard.scorers);

/// Repository is Premium-only (needs the v2 client). Null on the free key.
final playerStatsRepositoryProvider = Provider<PlayerStatsRepository?>((ref) {
  final v2 = ref.watch(sportsDbV2ClientProvider);
  if (v2 == null) return null;
  return PlayerStatsRepository(
    v1: ref.watch(footballApiClientProvider),
    v2: v2,
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Drives the leaderboard build. Kept **non-autoDispose** so the (potentially
/// long) first-time cache build keeps running while the user is on other tabs;
/// it restarts automatically when the league or season changes.
final statsControllerProvider =
    NotifierProvider<StatsController, StatsState>(StatsController.new);

class StatsController extends Notifier<StatsState> {
  int _runToken = 0;

  @override
  StatsState build() {
    final league = ref.watch(selectedLeagueProvider);
    final season = ref.watch(seasonProvider);
    final repo = ref.watch(playerStatsRepositoryProvider);

    final token = ++_runToken;
    if (repo == null) {
      return StatsState.premiumRequired;
    }
    Future<void>(() => _run(token, repo, league, season));
    return const StatsState(phase: StatsPhase.building);
  }

  /// Re-checks the schedule for newly-finished matches and processes them.
  /// Cached matches are reused, so this is cheap after the first build.
  Future<void> refresh() async {
    final repo = ref.read(playerStatsRepositoryProvider);
    if (repo == null) return;
    final token = ++_runToken;
    await _run(
      token,
      repo,
      ref.read(selectedLeagueProvider),
      ref.read(seasonProvider),
      refreshEventList: true,
    );
  }

  Future<void> _run(
    int token,
    PlayerStatsRepository repo,
    League league,
    int season, {
    bool refreshEventList = false,
  }) async {
    try {
      await repo.aggregate(
        league: league,
        season: season,
        refreshEventList: refreshEventList,
        isCancelled: () => token != _runToken,
        onProgress: (p) {
          if (token != _runToken) return;
          state = StatsState(
            phase: StatsPhase.building,
            board: p.board,
            processed: p.processed,
            total: p.total,
          );
        },
      );
      if (token == _runToken) {
        state = state.copyWith(phase: StatsPhase.done);
      }
    } catch (e) {
      if (token == _runToken) {
        state = state.copyWith(phase: StatsPhase.error, error: e);
      }
    }
  }
}
