import 'package:dio/dio.dart';

import '../../models/fixture.dart';
import '../../models/team_standing.dart';
import 'api_exception.dart';

/// Thin client over TheSportsDB v1 REST API.
///
/// * Auth: the API key is a path segment. The shared free key is `123`; a
///   Premium key can be supplied via [apiKey] to lift the free-tier limits.
/// * The free key fully supports league tables (including current seasons) but
///   heavily limits event/schedule endpoints.
class FootballApiClient {
  FootballApiClient({this.apiKey, Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (status) => status != null && status < 500,
          ),
        );
  }

  static const _baseUrl = 'https://www.thesportsdb.com/api/v1/json';
  static const _freeKey = '123';

  final String? apiKey;
  late final Dio _dio;

  /// The key used in the request path: the user's key if set, else the free key.
  String get _key {
    final k = apiKey?.trim();
    return (k == null || k.isEmpty) ? _freeKey : k;
  }

  /// League table (standings) for a league/season. Works on the free key for
  /// featured soccer leagues, including the current season.
  Future<List<TeamStanding>> getStandings({
    required int leagueId,
    required String season,
  }) async {
    final body = await _get('/$_key/lookuptable.php', query: {
      'l': leagueId,
      's': season,
    });
    final table = body['table'];
    if (table is! List) return const [];
    return table
        .whereType<Map<String, dynamic>>()
        .map(TeamStanding.fromJson)
        .toList();
  }

  /// All events for a league season. On the free key this is capped to the
  /// first 15 events; a Premium key returns the full schedule.
  Future<List<Fixture>> getSeasonEvents({
    required int leagueId,
    required String season,
  }) async {
    final body = await _get('/$_key/eventsseason.php', query: {
      'id': leagueId,
      's': season,
    });
    final events = body['events'];
    if (events is! List) return const [];
    return events
        .whereType<Map<String, dynamic>>()
        .map(Fixture.fromJson)
        .toList();
  }

  /// A team's last few events (home & away). Premium returns up to 10; the free
  /// key returns a single home event. Parsed from the `results` field.
  Future<List<Fixture>> getTeamLastEvents({required int teamId}) async {
    final body = await _get('/$_key/eventslast.php', query: {'id': teamId});
    final events = body['results'];
    if (events is! List) return const [];
    return events
        .whereType<Map<String, dynamic>>()
        .map(Fixture.fromJson)
        .toList();
  }

  /// A team's next few upcoming events. Premium returns up to 10; the free key
  /// returns a single event. Parsed from the `events` field.
  Future<List<Fixture>> getTeamNextEvents({required int teamId}) async {
    final body = await _get('/$_key/eventsnext.php', query: {'id': teamId});
    final events = body['events'];
    if (events is! List) return const [];
    return events
        .whereType<Map<String, dynamic>>()
        .map(Fixture.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      if (res.statusCode == 429) {
        throw const ApiException(
          'Rate limit reached (30 requests/min on the free key). '
          'Wait a moment and try again.',
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
