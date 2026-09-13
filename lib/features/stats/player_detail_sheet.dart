import 'package:flutter/material.dart';

import '../../models/player_details.dart';
import 'player_stats.dart';
import 'player_stats_repository.dart';

Future<void> showPlayerDetailSheet(
  BuildContext context,
  PlayerStatsRepository repo,
  StatLine line,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _PlayerDetailSheet(repo: repo, line: line),
  );
}

class _PlayerDetailSheet extends StatefulWidget {
  const _PlayerDetailSheet({required this.repo, required this.line});

  final PlayerStatsRepository repo;
  final StatLine line;

  @override
  State<_PlayerDetailSheet> createState() => _PlayerDetailSheetState();
}

class _PlayerDetailSheetState extends State<_PlayerDetailSheet> {
  late Future<PlayerDetails?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.lookupPlayer(widget.line);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: FutureBuilder<PlayerDetails?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _PlayerSheetStatus(
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return _PlayerSheetStatus(
                child: _PlayerSheetMessage(
                  icon: Icons.cloud_off_outlined,
                  text: 'Couldn’t load player details.',
                  action: TextButton.icon(
                    onPressed: () => setState(
                      () => _future = widget.repo.lookupPlayer(widget.line),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
              );
            }
            final player = snapshot.data;
            if (player == null) {
              return _PlayerSheetStatus(
                child: _PlayerSheetMessage(
                  icon: Icons.person_search_outlined,
                  text: 'No player profile was found for ${widget.line.player}.',
                ),
              );
            }
            return _PlayerDetailBody(
              player: player,
              fallbackTeam: widget.line.team,
            );
          },
        ),
      ),
    );
  }
}

class _PlayerDetailBody extends StatelessWidget {
  const _PlayerDetailBody({required this.player, required this.fallbackTeam});

  final PlayerDetails player;
  final String? fallbackTeam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = <({String label, String value})>[
      if (player.position.isNotEmpty)
        (label: 'Position', value: player.position),
      if (player.nationality.isNotEmpty)
        (label: 'Nationality', value: player.nationality),
      if (player.dateBorn.isNotEmpty) (label: 'Born', value: player.dateBorn),
      if (player.birthLocation.isNotEmpty)
        (label: 'Birthplace', value: player.birthLocation),
      if (player.height.isNotEmpty) (label: 'Height', value: player.height),
      if (player.weight.isNotEmpty) (label: 'Weight', value: player.weight),
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Center(
          child: _PlayerAvatar(imageUrl: player.imageUrl),
        ),
        const SizedBox(height: 12),
        Text(
          player.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if ((player.team.isNotEmpty || (fallbackTeam ?? '').isNotEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            player.team.isNotEmpty ? player.team : fallbackTeam!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (info.isNotEmpty) ...[
          const SizedBox(height: 20),
          for (final item in info)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(item.label),
              subtitle: Text(item.value),
            ),
        ],
        if (player.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Bio', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(player.description),
        ],
      ],
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 44,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: const Icon(Icons.person_outline, size: 40),
      );
    }
    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: 44,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: const Icon(Icons.person_outline, size: 40),
        ),
      ),
    );
  }
}

class _PlayerSheetStatus extends StatelessWidget {
  const _PlayerSheetStatus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Center(child: child),
    );
  }
}

class _PlayerSheetMessage extends StatelessWidget {
  const _PlayerSheetMessage({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}
