import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../ai/ai_log.dart';
import 'recap_providers.dart';

/// The recap block shown on the match goals sheet for finished fixtures.
///
/// Shows the deterministic template immediately; when on-device generation is
/// available the text is replaced by the model rewrite and labelled as such.
class RecapSection extends ConsumerStatefulWidget {
  const RecapSection({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<RecapSection> createState() => _RecapSectionState();
}

class _RecapSectionState extends ConsumerState<RecapSection> {
  bool _showFacts = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.fixture.isFinished) return const SizedBox.shrink();

    final request = RecapRequest(fixture: widget.fixture);
    final recap = ref.watch(recapProvider(request));

    // Timeline still loading: a small spinner, not a blank block.
    if (recap.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final theme = Theme.of(context);
    final state = recap.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final result = state.result;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (state.modelPending)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showFacts = !_showFacts),
                child: Text(_showFacts ? 'Hide facts' : 'Show facts'),
              ),
            ],
          ),
          if (_showFacts)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The on-device rewrite replaces the plain fact lines
                    // in prose; the fact lines stay below it.
                    if (result.aiWritten) ...[
                      Text(result.text, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Written by on-device AI',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final line in result.facts.toFactLines())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(line, style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text('AI diagnostics', style: theme.textTheme.bodySmall),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              ValueListenableBuilder<List<String>>(
                valueListenable: AiLog.lines,
                builder: (context, lines, _) => Text(
                  lines.isEmpty
                      ? 'No on-device AI events yet.'
                      : lines.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
