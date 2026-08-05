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

/// All fixtures for a given team in the currently selected season.
final teamFixturesProvider =
    FutureProvider.autoDispose.family<List<Fixture>, int>((ref, teamId) {
  final season = ref.watch(seasonProvider);
  return ref
      .watch(teamRepositoryProvider)
      .getSeasonFixtures(teamId: teamId, season: season);
});
