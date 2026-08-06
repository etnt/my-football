import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart' show seasonProvider;
import 'team_repository.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(
    client: ref.watch(footballApiClientProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Identifies a team within its league for the fixtures lookup.
typedef TeamRef = ({int teamId, int leagueId});

/// All fixtures for a given team in the currently selected season.
final teamFixturesProvider =
    FutureProvider.autoDispose.family<List<Fixture>, TeamRef>((ref, ref2) {
  final season = ref.watch(seasonProvider);
  final premium = ref.watch(isPremiumProvider);
  return ref.watch(teamRepositoryProvider).getSeasonFixtures(
        teamId: ref2.teamId,
        leagueId: ref2.leagueId,
        season: season,
        premium: premium,
      );
});
