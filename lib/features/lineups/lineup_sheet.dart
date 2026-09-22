import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../models/lineup_player.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart'
    show seasonProvider, selectedLeagueProvider;
import '../stats/player_detail_sheet.dart';
import '../stats/player_stats_repository.dart' show PlayerStatsRepository;
import '../stats/stats_providers.dart' show playerStatsRepositoryProvider;
import '../team/team_providers.dart';

/// Line-up rows for one match, fetched only when its sheet is opened.
/// Coverage varies by competition (e.g. none for Allsvenskan), so an empty
/// result is a valid outcome the sheet explains.
final lineupProvider =
    FutureProvider.autoDispose.family<List<LineupPlayer>, int>((ref, eventId) {
  return ref.watch(lineupRepositoryProvider).getLineup(eventId: eventId);
});

/// Opens the line-up sheet for one match. When [teamId] is given, only that
/// team's players are shown (the "latest line-up" entry point); otherwise the
/// sheet offers a home/away toggle (the per-match entry point).
Future<void> showLineupSheet(
  BuildContext context, {
  required Fixture fixture,
  int? teamId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LineupSheet(fixture: fixture, teamId: teamId),
  );
}

/// Opens the line-up of [teamId]'s most recent finished match in the selected
/// league/season — the standings-table entry point (issue #8).
Future<void> showLatestTeamLineup(
  BuildContext context,
  WidgetRef ref, {
  required int teamId,
  required String teamName,
}) async {
  final league = ref.read(selectedLeagueProvider);
  final season = ref.read(seasonProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final fixtures = await ref
        .read(teamRepositoryProvider)
        .getSeasonFixtures(teamId: teamId, leagueId: league.id, season: season);
    // The list is sorted newest-first; the first finished match is the latest.
    Fixture? latest;
    for (final fixture in fixtures) {
      if (fixture.isFinished) {
        latest = fixture;
        break;
      }
    }
    if (latest == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No finished $teamName match this season has a line-up yet.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await showLineupSheet(context, fixture: latest, teamId: teamId);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not load the line-up. Check your connection and try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Most the sheet may occupy, so the match header stays visible.
const _maxHeightFactor = 0.8;

/// Height reserved for the loading/error/empty states.
const _statusAreaHeight = 180.0;

/// The match line-up sheet: home/away toggle (per-match entry point), a
/// Starting XI section, an optional Substitutes section, and tap-through to
/// the player info sheet (issue #8).
class LineupSheet extends ConsumerStatefulWidget {
  const LineupSheet({super.key, required this.fixture, this.teamId});

  final Fixture fixture;
  final int? teamId;

  @override
  ConsumerState<LineupSheet> createState() => _LineupSheetState();
}

class _LineupSheetState extends ConsumerState<LineupSheet> {
  late int _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _selectedTeamId = widget.teamId ?? widget.fixture.homeId;
  }

  int _bySquadNumber(LineupPlayer a, LineupPlayer b) {
    final na = int.tryParse(a.squadNumber) ?? 999;
    final nb = int.tryParse(b.squadNumber) ?? 999;
    return na.compareTo(nb);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineup = ref.watch(lineupProvider(widget.fixture.id));
    final maxHeight = MediaQuery.sizeOf(context).height * _maxHeightFactor;
    final repo = ref.watch(playerStatsRepositoryProvider);

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
                        Text(
                          'Starting lineup',
                          style: theme.textTheme.titleLarge,
                        ),
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
            if (widget.teamId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: widget.fixture.homeId,
                      label: Text(
                        widget.fixture.homeName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: widget.fixture.awayId,
                      label: Text(
                        widget.fixture.awayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_selectedTeamId},
                  onSelectionChanged: (selection) =>
                      setState(() => _selectedTeamId = selection.first),
                ),
              ),
            const Divider(height: 1),
            Flexible(child: _buildBody(lineup, repo)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<LineupPlayer>> lineup,
    PlayerStatsRepository? repo,
  ) {
    return lineup.when(
      loading: () => const _StatusArea(child: CircularProgressIndicator()),
      error: (_, _) => _StatusArea(
        child: _LineupMessage(
          icon: Icons.cloud_off_outlined,
          text: 'Couldn’t load the line-up.',
          action: TextButton.icon(
            onPressed: () => ref.invalidate(lineupProvider(widget.fixture.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ),
      data: (players) {
        final xi = players
            .where((p) => p.teamId == _selectedTeamId && !p.isSubstitute)
            .toList()
          ..sort(_bySquadNumber);
        final subs = players
            .where((p) => p.teamId == _selectedTeamId && p.isSubstitute)
            .toList()
          ..sort(_bySquadNumber);
        if (xi.isEmpty && subs.isEmpty) {
          return const _StatusArea(
            child: _LineupMessage(
              icon: Icons.groups_outlined,
              text: 'No lineup data is available for this match.',
            ),
          );
        }
        void openPlayer(LineupPlayer player) =>
            showPlayerDetailSheetById(context, repo!, player.playerId);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            const _SectionLabel('Starting XI'),
            for (final player in xi)
              _LineupRow(
                player: player,
                onTap: repo == null ? null : () => openPlayer(player),
              ),
            if (subs.isNotEmpty) ...[
              const _SectionLabel('Substitutes'),
              for (final player in subs)
                _LineupRow(
                  player: player,
                  onTap: repo == null ? null : () => openPlayer(player),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _LineupRow extends StatelessWidget {
  const _LineupRow({required this.player, this.onTap});

  final LineupPlayer player;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      dense: true,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: player.squadNumber.isEmpty
            ? const Icon(Icons.person_outline, size: 20)
            : Text(player.squadNumber, style: theme.textTheme.labelLarge),
      ),
      title: Text(player.name),
      subtitle: player.position.isEmpty
          ? null
          : Text(
              player.position,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing: onTap != null
          ? Icon(Icons.chevron_right, size: 20, color: scheme.outline)
          : null,
      onTap: onTap,
    );
  }
}

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

class _LineupMessage extends StatelessWidget {
  const _LineupMessage({required this.icon, required this.text, this.action});

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
