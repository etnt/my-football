import 'package:flutter/material.dart';

import '../../../models/team_standing.dart';

/// A compact, mobile-friendly standings table.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.standings, this.onTapTeam});

  final List<TeamStanding> standings;
  final void Function(TeamStanding standing)? onTapTeam;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: standings.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) return const _HeaderRow();
        final standing = standings[index - 1];
        return _StandingRow(
          standing: standing,
          onTap: onTapTeam == null ? null : () => onTapTeam!(standing),
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: style)),
          const SizedBox(width: 32),
          Expanded(child: Text('Team', style: style)),
          _cell('P', style),
          _cell('GD', style),
          _cell('Pts', style),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.standing, this.onTap});

  final TeamStanding standing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('${standing.rank}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 32,
              child: standing.teamLogo.isEmpty
                  ? const Icon(Icons.shield_outlined, size: 22)
                  : Image.network(
                      standing.teamLogo,
                      width: 22,
                      height: 22,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.shield_outlined, size: 22),
                    ),
            ),
            Expanded(
              child: Text(
                standing.teamName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _cell('${standing.played}', null),
            _cell(_signed(standing.goalsDiff), null),
            _cell(
              '${standing.points}',
              const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
}

Widget _cell(String text, TextStyle? style) => SizedBox(
      width: 40,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
