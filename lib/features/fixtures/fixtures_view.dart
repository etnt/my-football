import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import 'fixtures_providers.dart';
import 'fixtures_repository.dart';
import 'widgets/fixture_tile.dart';

/// The matches body: a Results/Upcoming toggle plus the fixture list.
class FixturesView extends ConsumerWidget {
  const FixturesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(fixturesModeProvider);
    final fixtures = ref.watch(fixturesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<FixturesMode>(
            segments: const [
              ButtonSegment(
                value: FixturesMode.results,
                label: Text('Results'),
                icon: Icon(Icons.history),
              ),
              ButtonSegment(
                value: FixturesMode.upcoming,
                label: Text('Upcoming'),
                icon: Icon(Icons.event),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) =>
                ref.read(fixturesModeProvider.notifier).state = selection.first,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(fixturesProvider.notifier).refresh(),
            child: fixtures.when(
              data: (matches) => matches.isEmpty
                  ? MessageView(
                      icon: Icons.info_outline,
                      text: mode == FixturesMode.results
                          ? 'No recent results for this selection.'
                          : 'No upcoming matches for this selection.',
                    )
                  : _GroupedFixtureList(matches: matches),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ApiErrorView(error: error),
            ),
          ),
        ),
      ],
    );
  }
}

/// A fixture list grouped into collapsible matchweek sections. The first
/// (top) matchweek starts expanded; the rest are collapsed so it's easy to
/// scan the weeks and tap one open.
class _GroupedFixtureList extends StatelessWidget {
  const _GroupedFixtureList({required this.matches});

  final List<Fixture> matches;

  @override
  Widget build(BuildContext context) {
    final groups = _group(matches);
    return ListView.builder(
      // Preserves each section's expanded/collapsed state while scrolling.
      key: const PageStorageKey('fixtures-groups'),
      itemCount: groups.length,
      itemBuilder: (context, i) => _MatchweekSection(
        group: groups[i],
        initiallyExpanded: i == 0,
      ),
    );
  }

  /// Buckets the (already round-sorted) fixtures into ordered round groups.
  static List<_RoundGroup> _group(List<Fixture> matches) {
    final groups = <_RoundGroup>[];
    for (final f in matches) {
      if (groups.isEmpty || groups.last.round != f.round) {
        groups.add(_RoundGroup(f.round, [f]));
      } else {
        groups.last.matches.add(f);
      }
    }
    return groups;
  }
}

/// A single collapsible matchweek: a tappable header plus its fixtures.
class _MatchweekSection extends StatelessWidget {
  const _MatchweekSection({
    required this.group,
    required this.initiallyExpanded,
  });

  final _RoundGroup group;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = group.matches.length;
    return Column(
      children: [
        ExpansionTile(
          // Keeps this section's state even when scrolled off-screen.
          key: PageStorageKey('mw-${group.round ?? 'other'}'),
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          backgroundColor: scheme.secondaryContainer,
          collapsedBackgroundColor: scheme.secondaryContainer,
          iconColor: scheme.onSecondaryContainer,
          collapsedIconColor: scheme.onSecondaryContainer,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            group.round == null ? 'Other matches' : 'Matchweek ${group.round}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
            ),
          ),
          subtitle: Text(
            '$count ${count == 1 ? 'match' : 'matches'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
            ),
          ),
          children: [
            // ExpansionTile's backgroundColor fills the whole expanded tile;
            // paint the fixtures back onto the normal surface so only the
            // header strip carries the accent colour.
            ColoredBox(
              color: scheme.surface,
              child: Column(
                children: [
                  const Divider(height: 1),
                  for (final f in group.matches) ...[
                    FixtureTile(fixture: f),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// An ordered group of fixtures sharing a matchweek (`round`).
class _RoundGroup {
  _RoundGroup(this.round, this.matches);
  final int? round;
  final List<Fixture> matches;
}
