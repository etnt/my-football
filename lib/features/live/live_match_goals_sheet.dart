import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../models/goal_event.dart';
import 'live_providers.dart';

/// A quick summary of the goals recorded for an ongoing match.
class LiveMatchGoalsSheet extends ConsumerWidget {
  const LiveMatchGoalsSheet({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(matchTimelineProvider(fixture.id));
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.55,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Goals', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '${fixture.homeName} ${fixture.homeGoals ?? 0}–'
                          '${fixture.awayGoals ?? 0} ${fixture.awayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: timeline.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _TimelineMessage(
                  icon: Icons.cloud_off_outlined,
                  text: 'Couldn’t load goal details.',
                  action: TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(matchTimelineProvider(fixture.id)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
                data: (value) {
                  if (value.goals.isEmpty) {
                    return const _TimelineMessage(
                      icon: Icons.sports_soccer_outlined,
                      text: 'Goal details aren’t available yet.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: value.goals.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _GoalRow(goal: value.goals[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final GoalEvent goal;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (goal.team.isNotEmpty) goal.team,
      if (goal.assist != null) 'Assist: ${goal.assist}',
      if (goal.penalty) 'Penalty',
      if (goal.ownGoal) 'Own goal',
    ];

    return ListTile(
      leading: SizedBox(
        width: 42,
        child: Text(
          goal.minute == null ? '—' : "${goal.minute}'",
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(goal.scorer.isEmpty ? 'Unknown scorer' : goal.scorer),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: const Icon(Icons.sports_soccer, size: 20),
    );
  }
}

class _TimelineMessage extends StatelessWidget {
  const _TimelineMessage({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
