import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/stats/player_stats.dart';
import 'package:my_football/features/stats/player_stats_repository.dart';
import 'package:my_football/features/stats/stats_providers.dart';
import 'package:my_football/features/stats/stats_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FixedStatsController extends StatsController {
  _FixedStatsController(this.fixedState);

  final StatsState fixedState;

  @override
  StatsState build() => fixedState;
}

StatsState _stateWithRows() {
  return const StatsState(
    phase: StatsPhase.done,
    board: Leaderboards(
      scorers: [StatLine('Erling Haaland', 3, team: 'Manchester City')],
    ),
  );
}

Future<PlayerStatsRepository> _repo() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _EmptyAdapter();
  final v1 = FootballApiClient(
    apiKey: 'p',
    dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter,
  );
  final v2 = SportsDbV2Client(
    apiKey: 'p',
    dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter
      ..options.headers = {'X-API-KEY': 'p'}
      ..options.validateStatus = (status) => status != null && status < 500,
  );
  return PlayerStatsRepository(v1: v1, v2: v2, cache: CacheStore(prefs));
}

Widget _host({
  required StatsState state,
  required PlayerStatsRepository? repo,
}) {
  return ProviderScope(
    overrides: [
      statsControllerProvider.overrideWith(() => _FixedStatsController(state)),
      playerStatsRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(home: Scaffold(body: StatsView())),
  );
}

void main() {
  testWidgets('shows the player hint only when drill-down is available',
      (tester) async {
    final repo = await _repo();

    await tester.pumpWidget(_host(state: _stateWithRows(), repo: repo));
    await tester.pump();

    expect(find.text('Tap a player for details.'), findsOneWidget);
    final enabledTile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(enabledTile.onTap, isNotNull);

    await tester.pumpWidget(_host(state: _stateWithRows(), repo: null));
    await tester.pump();

    expect(find.text('Tap a player for details.'), findsNothing);
    final disabledTile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(disabledTile.onTap, isNull);
  });
}
