import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import 'player_stats.dart';
import 'stats_providers.dart';

/// The stats body: a Scorers/Assists/Cards toggle plus a ranked leaderboard
/// that fills in live while the season's matches are analysed.
class StatsView extends ConsumerWidget {
  const StatsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(statsBoardProvider);
    final stats = ref.watch(statsControllerProvider);

    if (stats.phase == StatsPhase.premiumRequired) {
      return const MessageView(
        icon: Icons.workspace_premium_outlined,
        text: 'Player stats need a Premium key. Add one in Settings.',
      );
    }
    if (stats.phase == StatsPhase.error) {
      return ApiErrorView(error: stats.error ?? 'Could not build stats.');
    }

    final lines = switch (board) {
      StatsBoard.scorers => stats.board.scorers,
      StatsBoard.assists => stats.board.assists,
      StatsBoard.cards => stats.board.cards,
    };
    final emptyText = switch (board) {
      StatsBoard.scorers => 'No goals recorded for this selection.',
      StatsBoard.assists => 'No assists recorded for this selection.',
      StatsBoard.cards => 'No cards recorded for this selection.',
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<StatsBoard>(
            segments: const [
              ButtonSegment(
                value: StatsBoard.scorers,
                label: Text('Scorers'),
                icon: Icon(Icons.sports_soccer),
              ),
              ButtonSegment(
                value: StatsBoard.assists,
                label: Text('Assists'),
                icon: Icon(Icons.handshake_outlined),
              ),
              ButtonSegment(
                value: StatsBoard.cards,
                label: Text('Cards'),
                icon: Icon(Icons.style_outlined),
              ),
            ],
            selected: {board},
            onSelectionChanged: (selection) =>
                ref.read(statsBoardProvider.notifier).state = selection.first,
          ),
        ),
        if (stats.isBuilding) _BuildProgress(stats: stats),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(statsControllerProvider.notifier).refresh(),
            child: lines.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: Center(
                          child: stats.isBuilding
                              ? const CircularProgressIndicator()
                              : MessageView(
                                  icon: Icons.info_outline,
                                  text: emptyText,
                                ),
                        ),
                      ),
                    ],
                  )
                : _LeaderboardList(lines: lines, board: board),
          ),
        ),
      ],
    );
  }
}

/// Thin progress strip shown while matches are still being analysed.
class _BuildProgress extends StatelessWidget {
  const _BuildProgress({required this.stats});

  final StatsState stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stats.total;
    final value = total > 0 ? stats.processed / total : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total > 0
                ? 'Analysing matches… ${stats.processed}/$total'
                : 'Loading schedule…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: value, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.lines, required this.board});

  final List<StatLine> lines;
  final StatsBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView.separated(
      key: const PageStorageKey('stats-leaderboard'),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final line = lines[i];
        final rank = i + 1;
        final parts = <String>[
          if (line.team != null && line.team!.isNotEmpty) line.team!,
          if (board == StatsBoard.scorers && line.penalties > 0)
            '${line.penalties} pen',
          if (board == StatsBoard.cards && line.yellows > 0) '${line.yellows} 🟨',
          if (board == StatsBoard.cards && line.reds > 0) '${line.reds} 🟥',
        ];
        final subtitle = parts.isEmpty ? null : parts.join(' · ');
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            child: Text('$rank', style: theme.textTheme.labelLarge),
          ),
          title: Text(line.player),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          trailing: Text(
            '${line.value}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        );
      },
    );
  }
}
