import 'package:dio/dio.dart';

import '../../models/card_event.dart';
import '../../models/fixture.dart';
import '../../models/goal_event.dart';
import '../../models/match_timeline.dart';
import 'api_exception.dart';

/// Client for TheSportsDB **v2** REST API, which is Premium-only.
///
/// * Base URL: `https://www.thesportsdb.com/api/v2/json`.
/// * Auth: the Premium key is sent in the `X-API-KEY` header.
/// * Errors are reported via standard HTTP status codes.
///
/// v2 is used for capabilities that v1 lacks — primarily livescores.
class SportsDbV2Client {
  SportsDbV2Client({required this.apiKey, this.onRateLimited, Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'X-API-KEY': apiKey},
            validateStatus: (status) => status != null && status < 500,
          ),
        );
  }

  static const _baseUrl = 'https://www.thesportsdb.com/api/v2/json';

  final String apiKey;

  /// Called when a request is throttled (HTTP 429), so the UI can react.
  final void Function()? onRateLimited;
  late final Dio _dio;

  /// Current live matches for a league. Returns an empty list when nothing is
  /// in play (e.g. off-season). Parsed from the `livescore` field.
  Future<List<Fixture>> getLiveScores({required int leagueId}) async {
    final body = await _get('/livescore/$leagueId');
    final scores = body['livescore'];
    if (scores is! List) return const [];
    return scores
        .whereType<Map<String, dynamic>>()
        .map(Fixture.fromV2Json)
        .toList();
  }

  /// All goals and cards in a finished match, parsed from the event timeline.
  /// Each goal row carries the scorer plus an optional assist, and each card row
  /// the booked player — so this single call feeds the scorer, assist and card
  /// leaderboards. Non-goal/card rows (subs) are ignored. Parsed from the
  /// `lookup` field.
  Future<MatchTimeline> getEventTimeline({required int eventId}) async {
    final body = await _get('/lookup/event_timeline/$eventId');
    final rows = body['lookup'];
    if (rows is! List) return const MatchTimeline();
    final maps = rows.whereType<Map<String, dynamic>>().toList();
    return MatchTimeline(
      goals: maps
          .where((r) => (r['strTimeline'] as String?)?.trim() == 'Goal')
          .map(GoalEvent.fromTimelineJson)
          .toList(),
      cards: maps
          .where((r) => (r['strTimeline'] as String?)?.trim() == 'Card')
          .map(CardEvent.fromTimelineJson)
          .toList(),
    );
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await _dio.get<dynamic>(path);
      final code = res.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw const ApiException(
          'Your Premium key was rejected. Check it in Settings.',
        );
      }
      if (code == 429) {
        onRateLimited?.call();
        throw const ApiException(
          'Rate limit reached (100 requests/min). Try again shortly.',
        );
      }
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Unexpected response from the server.');
      }
      return data;
    } on DioException catch (e) {
      throw ApiException(_mapDioError(e));
    }
  }

  String _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The request timed out. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Are you online?';
      default:
        return 'Network error: ${e.message ?? 'unknown'}.';
    }
  }

  void close() => _dio.close(force: true);
}
