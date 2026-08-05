import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => FixtureTile(fixture: matches[i]),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ApiErrorView(error: error),
            ),
          ),
        ),
      ],
    );
  }
}
