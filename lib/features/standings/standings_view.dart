import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../shared/widgets/api_error_view.dart';
import '../../shared/widgets/message_view.dart';
import '../settings/settings_screen.dart';
import '../team/team_detail_screen.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

/// The league table body (hosted inside the home shell).
class StandingsView extends ConsumerWidget {
  const StandingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(standingsProvider.notifier).refresh(),
      child: standings.when(
        data: (rows) => rows.isEmpty
            ? const MessageView(
                icon: Icons.info_outline,
                text: 'No standings available for this selection.',
              )
            : Column(
                children: [
                  if (!isPremium) const _FreeTierBanner(),
                  Expanded(
                    child: StandingsTable(
                      standings: rows,
                      onTapTeam: (team) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamDetailScreen(
                            teamId: team.teamId,
                            leagueId: ref.read(selectedLeagueProvider).id,
                            teamName: team.teamName,
                            teamLogo: team.teamLogo,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ApiErrorView(error: error),
      ),
    );
  }
}

/// Shown on the free key, where the table is capped at 5 rows. Tapping it
/// opens Settings to add a Premium key.
class _FreeTierBanner extends StatelessWidget {
  const _FreeTierBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 18, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Limited preview — go Premium for the full table, fixtures '
                  'and live scores.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

