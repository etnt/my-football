import 'package:flutter/material.dart';

import '../../../models/fixture.dart';

/// A single match row: home team, score/kick-off, away team, plus status.
class FixtureTile extends StatelessWidget {
  const FixtureTile({
    super.key,
    required this.fixture,
    this.onTap,
    this.onDoubleTap,
  });

  final Fixture fixture;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TeamLine(
                    name: fixture.homeName,
                    logo: fixture.homeLogo,
                    alignEnd: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _CentreBlock(fixture: fixture),
                ),
                Expanded(
                  child: _TeamLine(
                    name: fixture.awayName,
                    logo: fixture.awayLogo,
                    alignEnd: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _statusLabel(fixture),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CentreBlock extends StatelessWidget {
  const _CentreBlock({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showScore =
        (fixture.isFinished || fixture.isLive || fixture.progress != null) &&
        fixture.hasScore;

    if (showScore) {
      return Text(
        '${fixture.homeGoals} - ${fixture.awayGoals}',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: (fixture.isLive || fixture.progress != null)
              ? theme.colorScheme.error
              : null,
        ),
      );
    }

    return Text(
      _formatTime(fixture.dateUtc.toLocal()),
      style: theme.textTheme.titleMedium,
    );
  }
}

class _TeamLine extends StatelessWidget {
  const _TeamLine({
    required this.name,
    required this.logo,
    required this.alignEnd,
  });

  final String name;
  final String logo;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final logoWidget = logo.isEmpty
        ? const Icon(Icons.shield_outlined, size: 22)
        : Image.network(
            logo,
            width: 22,
            height: 22,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.shield_outlined, size: 22),
          );

    final text = Flexible(
      child: Text(
        name,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      ),
    );

    final children = alignEnd
        ? [text, const SizedBox(width: 8), logoWidget]
        : [logoWidget, const SizedBox(width: 8), text];

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: children,
    );
  }
}

String _statusLabel(Fixture f) {
  if (f.progress != null && f.progress!.isNotEmpty) {
    return f.progress!;
  }
  if (f.isLive) {
    return f.elapsed != null
        ? "${f.elapsed}'"
        : (f.statusLong.isEmpty ? 'LIVE' : f.statusLong);
  }
  if (f.isFinished) {
    return f.statusShort == 'FT' ? 'Full time' : f.statusShort;
  }
  return _formatDate(f.dateUtc.toLocal());
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
