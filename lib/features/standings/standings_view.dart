import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import '../team/team_detail_screen.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

/// The league table body (hosted inside the home shell).
class StandingsView extends ConsumerWidget {
  const StandingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(standingsProvider.notifier).refresh(),
      child: standings.when(
        data: (rows) => rows.isEmpty
            ? const MessageView(
                icon: Icons.info_outline,
                text: 'No standings available for this selection.',
              )
            : StandingsTable(
                standings: rows,
                onTapTeam: (team) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TeamDetailScreen(
                      teamId: team.teamId,
                      teamName: team.teamName,
                      teamLogo: team.teamLogo,
                    ),
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ApiErrorView(error: error),
      ),
    );
  }
}
