import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import '../fixtures/widgets/fixture_tile.dart';
import 'team_providers.dart';

class TeamDetailScreen extends ConsumerWidget {
  const TeamDetailScreen({
    super.key,
    required this.teamId,
    required this.leagueId,
    required this.teamName,
    required this.teamLogo,
  });

  final int teamId;
  final int leagueId;
  final String teamName;
  final String teamLogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamRef = (teamId: teamId, leagueId: leagueId);
    final fixtures = ref.watch(teamFixturesProvider(teamRef));

    return Scaffold(
      appBar: AppBar(title: Text(teamName)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(teamFixturesProvider(teamRef).future),
        child: fixtures.when(
          data: (all) => _TeamBody(
            teamId: teamId,
            teamName: teamName,
            teamLogo: teamLogo,
            fixtures: all,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ApiErrorView(error: error),
        ),
      ),
    );
  }
}

class _TeamBody extends StatelessWidget {
  const _TeamBody({
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.fixtures,
  });

  final int teamId;
  final String teamName;
  final String teamLogo;
  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) {
    if (fixtures.isEmpty) {
      return const MessageView(
        icon: Icons.info_outline,
        text: 'No fixtures found for this team and season.',
      );
    }

    final byDate = [...fixtures]..sort((a, b) => a.dateUtc.compareTo(b.dateUtc));
    final finished = byDate.where((f) => f.isFinished).toList();
    final upcoming = byDate.where((f) => !f.isFinished).toList();

    final recent = finished.reversed.take(5).toList();
    final next = upcoming.take(5).toList();
    // Last five results in chronological order for the form strip.
    final form = finished
        .map((f) => f.resultFor(teamId))
        .whereType<String>()
        .toList();
    final recentForm = form.length <= 5 ? form : form.sublist(form.length - 5);

    return ListView(
      children: [
        _Header(teamName: teamName, teamLogo: teamLogo, form: recentForm),
        if (recent.isNotEmpty) ...[
          const _SectionHeader('Recent results'),
          for (final f in recent) FixtureTile(fixture: f),
        ],
        if (next.isNotEmpty) ...[
          const _SectionHeader('Upcoming'),
          for (final f in next) FixtureTile(fixture: f),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.teamName,
    required this.teamLogo,
    required this.form,
  });

  final String teamName;
  final String teamLogo;
  final List<String> form;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (teamLogo.isNotEmpty)
            Image.network(
              teamLogo,
              width: 64,
              height: 64,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.shield_outlined, size: 64),
            )
          else
            const Icon(Icons.shield_outlined, size: 64),
          const SizedBox(height: 8),
          Text(teamName, style: Theme.of(context).textTheme.titleLarge),
          if (form.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Form  '),
                for (final r in form)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _FormBadge(result: r),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FormBadge extends StatelessWidget {
  const _FormBadge({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'W' => Colors.green,
      'L' => Colors.red,
      _ => Colors.grey,
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        result,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
