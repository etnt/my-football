import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../models/goal_event.dart';
import 'live_providers.dart';

/// A quick summary of the goals recorded for an ongoing match.
///
/// The sheet hugs its content: with a couple of goals it is short, with many
/// it grows up to a screen-height cap and the goal list scrolls (with a
/// visible scrollbar, so it's clear more rows are available).
class LiveMatchGoalsSheet extends ConsumerStatefulWidget {
  const LiveMatchGoalsSheet({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<LiveMatchGoalsSheet> createState() =>
      _LiveMatchGoalsSheetState();
}

/// Most the sheet may occupy, so the match header always stays visible.
const _maxHeightFactor = 0.7;

/// Height reserved for the loading/error/empty states, so they don't
/// collapse the sheet to a thin strip.
const _statusAreaHeight = 180.0;

class _LiveMatchGoalsSheetState extends ConsumerState<LiveMatchGoalsSheet> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(matchTimelineProvider(widget.fixture.id));
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * _maxHeightFactor;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          '${widget.fixture.homeName} '
                          '${widget.fixture.homeGoals ?? 0}–'
                          '${widget.fixture.awayGoals ?? 0} '
                          '${widget.fixture.awayName}',
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
            Flexible(
              child: timeline.when(
                loading: () => const _StatusArea(
                  child: CircularProgressIndicator(),
                ),
                error: (_, _) => _StatusArea(
                  child: _TimelineMessage(
                    icon: Icons.cloud_off_outlined,
                    text: 'Couldn’t load goal details.',
                    action: TextButton.icon(
                      onPressed: () => ref.invalidate(
                        matchTimelineProvider(widget.fixture.id),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ),
                data: (value) {
                  if (value.goals.isEmpty) {
                    return const _StatusArea(
                      child: _TimelineMessage(
                        icon: Icons.sports_soccer_outlined,
                        text: 'Goal details aren’t available yet.',
                      ),
                    );
                  }
                  return Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _scrollController,
                      // Hug the content when it fits; clamp + scroll when
                      // it doesn't (Flexible/ConstrainedBox provide the cap).
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: value.goals.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _GoalRow(goal: value.goals[index]),
                    ),
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

/// Bounded container for non-scrollable sheet states (loading/error/empty).
class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _statusAreaHeight,
      width: double.infinity,
      child: Center(child: child),
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
