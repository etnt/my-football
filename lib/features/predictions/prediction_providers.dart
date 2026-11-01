import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fixtures/fixtures_providers.dart';
import '../standings/standings_providers.dart';
import 'prediction_calculator.dart';
import 'prediction_repository.dart';
import 'prediction_result.dart';

final predictionRepositoryProvider = Provider<PredictionRepository>((ref) {
  return PredictionRepository(
    standings: ref.watch(standingsRepositoryProvider),
    fixtures: ref.watch(fixturesRepositoryProvider),
  );
});

/// Identifies one prediction. `leagueId` and `season` make stale entries from
/// a league or season switch impossible: the family key changes and the old
/// provider is disposed (plan §3).
typedef PredictionKey = ({int fixtureId, int leagueId, int season});

/// The computed prediction for one fixture, built from cached data only
/// (REQ-008). Loads like `teamFixturesProvider` (PAT-001).
final predictionProvider = FutureProvider.autoDispose
    .family<PredictionResult, PredictionKey>((ref, key) async {
      final league = ref.watch(selectedLeagueProvider);
      final season = ref.watch(seasonProvider);
      final input = await ref
          .watch(predictionRepositoryProvider)
          .build(league: league, season: season, fixtureId: key.fixtureId);
      return const PredictionCalculator().calculate(input);
    });
