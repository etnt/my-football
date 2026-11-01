import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../shared/widgets/api_error_view.dart';
import '../standings/standings_providers.dart'
    show selectedLeagueProvider, seasonProvider;
import 'prediction_providers.dart';
import 'prediction_result.dart';

/// Opens the prediction sheet for an eligible upcoming [fixture].
///
/// The league and season are read before the sheet opens (the reminders
/// convention), so the numbers cannot change under the user while it is up.
Future<void> showPredictionSheet(
  BuildContext context,
  WidgetRef ref,
  Fixture fixture,
) {
  final league = ref.read(selectedLeagueProvider);
  final season = ref.read(seasonProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _PredictionSheet(fixture: fixture, leagueId: league.id, season: season),
  );
}

class _PredictionSheet extends ConsumerWidget {
  const _PredictionSheet({
    required this.fixture,
    required this.leagueId,
    required this.season,
  });

  final Fixture fixture;
  final int leagueId;
  final int season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kickoff = fixture.dateUtc.toLocal();
    final localizations = MaterialLocalizations.of(context);
    // One key for both the prediction and the AI summary request, so the
    // narration provider watches the exact same prediction member.
    final key = (fixtureId: fixture.id, leagueId: leagueId, season: season);
    final prediction = ref.watch(predictionProvider(key));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${fixture.homeName} vs ${fixture.awayName}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Text(
              '${localizations.formatMediumDate(kickoff)} '
              'at ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(kickoff))}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Scrollable and capped by the sheet height, so large text scales
            // never overflow the sheet (REQ-011). Only the data body scrolls:
            // the error view's message list needs bounded height.
            Flexible(
              child: prediction.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => error is PredictionUnavailable
                    ? _UnavailableView(reason: error.reason)
                    : ApiErrorView(error: error),
                data: (result) => SingleChildScrollView(
                  child: _PredictionBody(
                    fixture: fixture,
                    predictionKey: key,
                    result: result,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Not enough data" plus the concrete reason (REQ-007): no percentages.
class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Not enough data',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PredictionBody extends StatelessWidget {
  const _PredictionBody({
    required this.fixture,
    required this.predictionKey,
    required this.result,
  });

  final Fixture fixture;
  final PredictionKey predictionKey;
  final PredictionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percents = result.displayPercents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _verdictText(result),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _ChanceBar(percents: percents),
        const SizedBox(height: 8),
        // Percentages as text, not only as colour (REQ-011).
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('${fixture.homeName} ${percents[Outcome.home]}%'),
            Text('Draw ${percents[Outcome.draw]}%'),
            Text('${fixture.awayName} ${percents[Outcome.away]}%'),
          ],
        ),
        // Optional AI prose, only added once validated (Phase 5). It sits
        // above the deterministic reasons and never replaces them (CON-001).
        // It carries its own top margin, so the gap stays 12 when it is
        // hidden instead of doubling to 24.
        _AiSummary(fixture: fixture, predictionKey: predictionKey),
        const SizedBox(height: 12),
        Text(
          'Why this estimate?',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        for (final reason in result.reasons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• ${reason.text}'),
          ),
        for (final note in result.missingNotes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Estimate based on table and form. Not betting advice.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _verdictText(PredictionResult result) {
    final slight = result.isSlight ? ' – slight favourite' : '';
    return switch (result.verdict) {
      Verdict.homeWin => 'Home win$slight',
      Verdict.awayWin => 'Away win$slight',
      Verdict.closeDrawLikely => 'Close – draw likely',
    };
  }
}

/// The optional on-device AI summary (Phase 5). Watches only its own
/// narration provider; the sheet's `prediction.when` above still watches
/// only `predictionProvider`, so the deterministic content can never wait
/// for the model (CON-001). While the model is pending — or when it is
/// unavailable, slow or rejected — nothing is shown: no spinner, no
/// download (CON-002).
class _AiSummary extends ConsumerWidget {
  const _AiSummary({required this.fixture, required this.predictionKey});

  final Fixture fixture;
  final PredictionKey predictionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final narration = ref.watch(
      predictionNarrationProvider(
        NarrationRequest(fixture: fixture, key: predictionKey),
      ),
    );
    final text = narration.valueOrNull;
    if (text == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          // Mirrors the recap's wording; REQ-010 bans "odds"/"calibrated",
          // which this label avoids.
          'Written by on-device AI',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        Text(text, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// A single stacked bar of the three chances. Zero-percent sides are skipped
/// instead of getting an `Expanded(flex: 0)` (which would throw).
class _ChanceBar extends StatelessWidget {
  const _ChanceBar({required this.percents});

  final Map<Outcome, int> percents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <Widget>[
      for (final outcome in Outcome.values)
        if (percents[outcome]! > 0)
          Expanded(
            flex: percents[outcome]!,
            child: ColoredBox(
              color: switch (outcome) {
                Outcome.home => scheme.primary,
                Outcome.draw => scheme.outline,
                Outcome.away => scheme.tertiary,
              },
              child: const SizedBox(height: 10),
            ),
          ),
    ];
    if (segments.isEmpty) return const SizedBox(height: 10);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Row(children: segments),
    );
  }
}
