import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import '../fixtures/widgets/fixture_tile.dart';
import '../standings/standings_providers.dart' show selectedLeagueProvider;
import 'goal_alert.dart';
import 'live_providers.dart';

/// Live scores for the selected league (Premium only). Auto-refreshes while
/// this tab is visible, and fires a phone notification when a goal is scored.
class LiveScoresView extends ConsumerStatefulWidget {
  const LiveScoresView({super.key});

  @override
  ConsumerState<LiveScoresView> createState() => _LiveScoresViewState();
}

class _LiveScoresViewState extends ConsumerState<LiveScoresView> {
  final _monitor = LiveGoalMonitor();

  @override
  void initState() {
    super.initState();
    // Ask for notification permission as soon as the Live tab is shown, so a
    // later goal can actually ring the phone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(goalNotificationServiceProvider).ensureReady().ignore();
    });
  }

  Future<void> _notify(List<GoalAlert> alerts) async {
    if (alerts.isEmpty) return;
    final service = ref.read(goalNotificationServiceProvider);
    final allowed = await service.ensureReady();
    if (!allowed || !mounted) return;
    for (final alert in alerts) {
      try {
        await service.showGoal(alert);
      } catch (_) {
        // Notifications are best-effort; a plugin failure must not break Live.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // A league switch is a new set of matches — don't compare scores across
    // leagues, and don't treat the first snapshot of the new league as goals.
    ref.listen(selectedLeagueProvider, (_, _) => _monitor.reset());

    ref.listen(liveScoresProvider, (_, next) {
      next.whenData((matches) {
        final alerts = _monitor.ingest(matches);
        if (alerts.isEmpty) return;
        _notify(alerts);
      });
    });

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
          const SizedBox(width: 8),
          Text(
            '· Goal alerts on',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
