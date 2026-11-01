import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../providers/app_providers.dart';
import '../ai/ai_log.dart';
import '../ai/ai_providers.dart';
import '../fixtures/fixtures_providers.dart';
import '../standings/standings_providers.dart';
import 'prediction_calculator.dart';
import 'prediction_narrator.dart';
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

/// Builds [PredictionNarrator]s wired to the shared AI service and cache,
/// like `recapBuilderProvider`.
final predictionNarratorProvider = Provider<PredictionNarrator>((ref) {
  return PredictionNarrator(
    ai: ref.watch(aiServiceProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Identifies one AI summary request. Equality on the fixture id and the
/// prediction key, matching the way the sheet builds it.
class NarrationRequest {
  const NarrationRequest({required this.fixture, required this.key});

  final Fixture fixture;
  final PredictionKey key;

  @override
  bool operator ==(Object other) =>
      other is NarrationRequest &&
      other.fixture.id == fixture.id &&
      other.key == key;

  @override
  int get hashCode => Object.hash(fixture.id, key);
}

/// The optional on-device AI summary for one prediction, or null when
/// generation is unavailable, slow, fails or is rejected by the validator.
///
/// Never fails itself (CON-001): everything is swallowed into null so the
/// sheet always keeps the deterministic reasons. It watches the very same
/// `predictionProvider` member the sheet shows, so no repository data is
/// loaded twice.
final predictionNarrationProvider = FutureProvider.autoDispose
    .family<String?, NarrationRequest>((ref, request) async {
      try {
        final result = await ref.watch(predictionProvider(request.key).future);
        return await ref
            .watch(predictionNarratorProvider)
            .summarize(request.fixture, result);
      } on Object catch (e) {
        // A missing dependency (e.g. no SharedPreferences override), an
        // unavailable prediction or any model failure must never surface as
        // a provider error: the sheet shows the deterministic content
        // (CON-001). The type is logged and the message is not, because
        // exception messages can carry match data or the request URL
        // (CON-003).
        AiLog.add('prediction: narration failed (${e.runtimeType})');
        return null;
      }
    });
