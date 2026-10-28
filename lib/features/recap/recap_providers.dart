import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../ai/ai_log.dart';
import '../../models/fixture.dart';
import '../../models/match_timeline.dart';
import '../../providers/app_providers.dart';
import '../ai/ai_providers.dart';
import '../live/live_providers.dart';
import 'fact_sheet.dart';
import 'recap_builder.dart';

/// Builds [RecapBuilder]s wired to the shared AI service and cache.
final recapBuilderProvider = Provider<RecapBuilder>((ref) {
  return RecapBuilder(
    ai: ref.watch(aiServiceProvider),
    cache: CacheStore(ref.watch(sharedPreferencesProvider)),
  );
});

/// Identifies one recap request. Equality is on the fixture id only — the
/// competition is cosmetic and shouldn't recreate the notifier.
class RecapRequest {
  const RecapRequest({required this.fixture, this.competition});

  final Fixture fixture;
  final String? competition;

  @override
  bool operator ==(Object other) =>
      other is RecapRequest && other.fixture.id == fixture.id;

  @override
  int get hashCode => fixture.id.hashCode;
}

/// The current recap: the always-available template plus whether a model
/// rewrite is still in flight.
class RecapState {
  const RecapState({required this.result, required this.modelPending});

  final RecapResult result;
  final bool modelPending;
}

/// Loads the timeline, builds the fact sheet, shows the template immediately
/// and tries a model rewrite in the background.
class RecapNotifier
    extends AutoDisposeFamilyAsyncNotifier<RecapState, RecapRequest> {
  /// Set via [ref.onDispose]; `ref.mounted` isn't exposed on Riverpod 2.x
  /// refs, so this guards the background write against a disposed notifier.
  bool _disposed = false;

  @override
  FutureOr<RecapState> build(RecapRequest request) {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final fixture = request.fixture;
    final builder = ref.read(recapBuilderProvider);

    // 1. Timeline first: it feeds the fact sheet. A failure here means the
    //    recap is score-only, not broken.
    final timelineFuture = ref.watch(matchTimelineProvider(fixture.id).future);

    // 2. Build the fact sheet and the deterministic template.
    return timelineFuture
        .catchError((Object _, StackTrace _) => const MatchTimeline())
        .then((timeline) {
          final facts = FactSheet.build(
            fixture: fixture,
            timeline: timeline,
            competition: request.competition,
          );
          final template = builder.template(facts);

          // 3. Skip the model when the fact sheet can't support a rewrite —
          //    the builder owns that rule. The builder itself was resolved
          //    once at the top of build(), before the async gap, so this
          //    callback must not touch ref after an await.
          if (!builder.shouldTryModel(facts)) {
            AiLog.add('model skipped: no goal data (score only)');
            return RecapState(result: template, modelPending: false);
          }

          // 4. Fire the model rewrite in the background so the template shows
          //    immediately.
          _rewriteInBackground(facts, builder, template);
          return RecapState(result: template, modelPending: true);
        });
  }

  Future<void> _rewriteInBackground(
    FactSheet facts,
    RecapBuilder builder,
    RecapResult template,
  ) async {
    final model = await builder.tryModelRewrite(facts);
    // Guard: the sheet may have been closed while we were generating.
    if (_disposed) return;
    state = AsyncData(
      RecapState(result: model ?? template, modelPending: false),
    );
  }
}

final recapProvider = AsyncNotifierProvider.autoDispose
    .family<RecapNotifier, RecapState, RecapRequest>(RecapNotifier.new);
