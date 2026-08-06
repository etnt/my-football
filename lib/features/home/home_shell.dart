import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_version.dart';
import '../../models/league.dart';
import '../../providers/app_providers.dart';
import '../fixtures/fixtures_view.dart';
import '../live/live_scores_view.dart';
import '../settings/settings_screen.dart';
import '../standings/standings_providers.dart';
import '../standings/standings_view.dart';
import '../stats/stats_view.dart';

/// App shell: a shared app bar and league/season selector, with bottom-nav
/// tabs switching between the table, matches and (Premium) live views.
///
/// The body is swapped (not stacked) so the inactive tab's data provider is
/// disposed — keeping API usage low. Cached data means switching tabs back
/// doesn't cost a request within its TTL.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  // Seasons offered in the picker (starting year). The current season may be
  // sparse; older seasons usually have a complete table.
  static const _seasons = [2026, 2025, 2024, 2023, 2022, 2021];

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);

    // Surface a brief notice whenever an API request is throttled (HTTP 429).
    ref.listen<int>(rateLimitProvider, (previous, next) {
      if (next > (previous ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Rate limit reached — please wait a moment.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    });

    // Live and Stats are Premium-only tabs, appended after Matches.
    final bodies = <Widget>[
      const StandingsView(),
      const FixturesView(),
      if (isPremium) const StatsView(),
      if (isPremium) const LiveScoresView(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.table_rows_outlined),
        selectedIcon: Icon(Icons.table_rows),
        label: 'Table',
      ),
      const NavigationDestination(
        icon: Icon(Icons.sports_soccer_outlined),
        selectedIcon: Icon(Icons.sports_soccer),
        label: 'Matches',
      ),
      if (isPremium)
        const NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined),
          selectedIcon: Icon(Icons.leaderboard),
          label: 'Stats',
        ),
      if (isPremium)
        const NavigationDestination(
          icon: Icon(Icons.podcasts_outlined),
          selectedIcon: Icon(Icons.podcasts),
          label: 'Live',
        ),
    ];
    final index = _index.clamp(0, bodies.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            text: 'My Football',
            children: [
              TextSpan(
                text: '  $appVersion',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _LeaguePicker(),
          _SeasonPicker(seasons: _seasons),
          const Divider(height: 1),
          Expanded(child: bodies[index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}

class _LeaguePicker extends ConsumerWidget {
  const _LeaguePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLeagueProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final league in League.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(league.label),
                selected: league == selected,
                onSelected: (_) =>
                    ref.read(selectedLeagueProvider.notifier).state = league,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeasonPicker extends ConsumerWidget {
  const _SeasonPicker({required this.seasons});

  final List<int> seasons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(seasonProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('Season'),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: seasons.contains(season) ? season : seasons.first,
            items: [
              for (final year in seasons)
                DropdownMenuItem(
                  value: year,
                  child: Text('$year/${(year + 1) % 100}'),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(seasonProvider.notifier).state = value;
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Data by TheSportsDB',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
