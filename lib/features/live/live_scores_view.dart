import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import '../fixtures/widgets/fixture_tile.dart';
import 'live_providers.dart';

/// Live scores for the selected league (Premium only). Auto-refreshes while
/// this tab is visible.
class LiveScoresView extends ConsumerWidget {
  const LiveScoresView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveScoresProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(liveScoresProvider),
      child: live.when(
        data: (matches) {
          if (matches.isEmpty) {
            return const MessageView(
              icon: Icons.sports_soccer_outlined,
              text: 'No live matches in this league right now.\n'
                  'Scores update automatically when games kick off.',
            );
          }
          return ListView.separated(
            itemCount: matches.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) return const _LiveHeader();
              return FixtureTile(fixture: matches[index - 1]);
            },
          );
        },
        // Keep showing the last frame while re-polling; only surface hard errors.
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ApiErrorView(error: error),
      ),
    );
  }
}

class _LiveHeader extends StatelessWidget {
  const _LiveHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Text(
            'LIVE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
