import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/football_api_client.dart';
import '../../core/api/sportsdb_v2_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../models/league.dart';
import '../../models/match_timeline.dart';
import 'player_stats.dart';

/// Progress callback payload emitted after each match is processed.
class StatsProgress {
  const StatsProgress({
    required this.processed,
    required this.total,
    required this.board,
  });

  final int processed;
  final int total;
  final Leaderboards board;
}

/// Builds top-scorer / top-assist leaderboards by aggregating per-match
/// timelines from TheSportsDB v2.
///
/// The heavy lifting (one timeline call per finished match) is:
///  * **rate-limited** to [_targetPerMinute] to stay well under the Premium
///    100 req/min cap, with reactive back-off on HTTP 429;
///  * **cached permanently per event** — a finished match's timeline never
///    changes — so the full build is a one-time cost and any later refresh only
///    fetches newly-finished matches;
///  * **incremental & resumable** — an interrupted build picks up where it left
///    off because processed events are already in the cache.
class PlayerStatsRepository {
  PlayerStatsRepository({
    required this.v1,
    required this.v2,
    required this.cache,
    Duration? minRequestInterval,
  }) : _minInterval = minRequestInterval ?? _defaultInterval;

  final FootballApiClient v1;
  final SportsDbV2Client v2;
  final CacheStore cache;

  /// Conservative request budget while the cache warms up. The Premium cap is
  /// 100/min; we deliberately aim lower so bursts never trip a 429.
  static const _targetPerMinute = 50;
  static final Duration _defaultInterval =
      Duration(milliseconds: (60000 / _targetPerMinute).round());

  /// Minimum spacing between outgoing timeline requests (overridable in tests).
  final Duration _minInterval;

  /// How long a fetched-and-parsed match stays cached. Finished matches are
  /// immutable, so effectively forever.
  static const _eventTtl = Duration(days: 3650);

  /// The season-schedule list is cheap and can change (new matches finish), so
  /// it gets a short TTL and is force-refreshed on pull-to-refresh.
  static const _eventListTtl = Duration(hours: 6);

  /// How many rows to keep on each board.
  static const _topN = 40;

  /// In debug builds (e.g. running on the emulator) we don't need the full
  /// season leaderboard — cap the number of matches so the throttled build
  /// finishes in seconds. Release builds process every finished match.
  static const _debugMaxEvents = 30;

  DateTime _lastRequestStart = DateTime.fromMillisecondsSinceEpoch(0);

  /// Aggregates leaderboards for [league]/[season].
  ///
  /// [onProgress] is called after every match with the running partial board.
  /// [isCancelled] is polled frequently so a superseded build stops promptly.
  Future<void> aggregate({
    required League league,
    required int season,
    required bool Function() isCancelled,
    required void Function(StatsProgress) onProgress,
    bool refreshEventList = false,
  }) async {
    final events =
        await _finishedEvents(league, season, forceRefresh: refreshEventList);
    final capped = (kDebugMode && events.length > _debugMaxEvents)
        ? events.sublist(0, _debugMaxEvents)
        : events;
    final total = capped.length;

    final goals = <String, int>{};
    final penalties = <String, int>{};
    final assists = <String, int>{};
    final yellows = <String, int>{};
    final reds = <String, int>{};
    final teams = <String, String>{};
    var processed = 0;

    for (final event in capped) {
      if (isCancelled()) return;
      final timeline = await _eventTimeline(event.id, isCancelled: isCancelled);
      for (final g in timeline.goals) {
        if (!g.ownGoal && g.scorer.isNotEmpty) {
          goals[g.scorer] = (goals[g.scorer] ?? 0) + 1;
          if (g.penalty) {
            penalties[g.scorer] = (penalties[g.scorer] ?? 0) + 1;
          }
          if (g.team.isNotEmpty) teams[g.scorer] = g.team;
        }
        final a = g.assist;
        if (a != null && a.isNotEmpty) {
          assists[a] = (assists[a] ?? 0) + 1;
          if (g.team.isNotEmpty) teams[a] = g.team;
        }
      }
      for (final c in timeline.cards) {
        if (c.player.isEmpty) continue;
        if (c.red) {
          reds[c.player] = (reds[c.player] ?? 0) + 1;
        } else {
          yellows[c.player] = (yellows[c.player] ?? 0) + 1;
        }
        if (c.team.isNotEmpty) teams[c.player] = c.team;
      }
      processed++;
      onProgress(StatsProgress(
        processed: processed,
        total: total,
        board: _board(goals, penalties, assists, yellows, reds, teams),
      ));
    }
  }

  Leaderboards _board(
    Map<String, int> goals,
    Map<String, int> penalties,
    Map<String, int> assists,
    Map<String, int> yellows,
    Map<String, int> reds,
    Map<String, String> teams,
  ) {
    final scorers = goals.entries
        .map((e) => StatLine(
              e.key,
              e.value,
              penalties: penalties[e.key] ?? 0,
              team: teams[e.key],
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final assisters = assists.entries
        .map((e) => StatLine(e.key, e.value, team: teams[e.key]))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final booked = <String>{...yellows.keys, ...reds.keys}
        .map((p) {
          final y = yellows[p] ?? 0;
          final r = reds[p] ?? 0;
          return StatLine(p, y + r, yellows: y, reds: r, team: teams[p]);
        })
        .toList()
      // Most cards first; a red is worse than a yellow, so break ties on reds.
      ..sort((a, b) {
        final byTotal = b.value.compareTo(a.value);
        return byTotal != 0 ? byTotal : b.reds.compareTo(a.reds);
      });
    return Leaderboards(
      scorers: scorers.take(_topN).toList(),
      assists: assisters.take(_topN).toList(),
      cards: booked.take(_topN).toList(),
    );
  }

  /// The timeline (goals + cards) for a single event — from cache when present,
  /// otherwise fetched (rate-limited) and cached permanently.
  Future<MatchTimeline> _eventTimeline(
    int eventId, {
    required bool Function() isCancelled,
  }) async {
    final key = 'stats_ev2_$eventId';
    final cached = cache.readJson(key);
    if (cached != null &&
        cached.isFresh(_eventTtl) &&
        cached.data is Map<String, dynamic>) {
      return MatchTimeline.fromJson(cached.data as Map<String, dynamic>);
    }

    var attempt = 0;
    while (true) {
      await _gate();
      if (isCancelled()) return const MatchTimeline();
      try {
        final timeline = await v2.getEventTimeline(eventId: eventId);
        await cache.writeJson(key, timeline.toJson());
        return timeline;
      } on ApiException catch (e) {
        final rateLimited = e.message.contains('Rate limit');
        if (rateLimited && attempt < 3) {
          attempt++;
          await Future<void>.delayed(const Duration(seconds: 20));
          continue;
        }
        // Skip this match rather than aborting the whole build.
        return const MatchTimeline();
      }
    }
  }

  /// Blocks until enough time has passed since the last request start so we
  /// never exceed [_targetPerMinute].
  Future<void> _gate() async {
    final earliest = _lastRequestStart.add(_minInterval);
    final now = DateTime.now();
    if (now.isBefore(earliest)) {
      await Future<void>.delayed(earliest.difference(now));
    }
    _lastRequestStart = DateTime.now();
  }

  Future<List<Fixture>> _finishedEvents(
    League league,
    int season, {
    bool forceRefresh = false,
  }) async {
    final key = 'stats_events_${league.id}_$season';
    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.isFresh(_eventListTtl)) {
        return _decodeFixtures(cached.data);
      }
    }
    try {
      final all = await v1.getSeasonEvents(
        leagueId: league.id,
        season: apiSeason(season),
      );
      final finished = all.where((e) => e.isFinished).toList();
      await cache.writeJson(
        key,
        finished.map((e) => e.toJson()).toList(),
      );
      return finished;
    } catch (_) {
      final cached = cache.readJson(key);
      if (cached != null) return _decodeFixtures(cached.data);
      rethrow;
    }
  }

  List<Fixture> _decodeFixtures(Object? data) {
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(Fixture.fromJson)
        .toList();
  }
}
