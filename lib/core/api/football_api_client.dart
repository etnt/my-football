import 'package:dio/dio.dart';

import '../../models/account_status.dart';
import '../../models/fixture.dart';
import '../../models/rate_limit_info.dart';
import '../../models/team_standing.dart';
import 'api_exception.dart';

/// Thin client over the API-Football v3 (direct API-Sports host).
///
/// * Auth: `x-apisports-key` header.
/// * Every response carries rate-limit headers, which we surface via
///   [onRateLimit] so the UI can show "requests remaining today".
class FootballApiClient {
  FootballApiClient({this.apiKey, this.onRateLimit, Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            // Let us read the body for 4xx (invalid key etc.) rather than throw.
            validateStatus: (status) => status != null && status < 500,
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final key = apiKey;
          if (key != null && key.isNotEmpty) {
            options.headers['x-apisports-key'] = key;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _captureRateLimit(response.headers);
          handler.next(response);
        },
      ),
    );
  }

  static const _baseUrl = 'https://v3.football.api-sports.io';

  final String? apiKey;
  final void Function(RateLimitInfo info)? onRateLimit;
  late final Dio _dio;

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// Account & quota status. Also useful to validate a freshly entered key.
  Future<AccountStatus> getStatus() async {
    final body = await _get('/status');
    final response = body['response'];
    if (response is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response from /status.');
    }
    return AccountStatus.fromJson(response);
  }

  /// Standings for a league/season. Leagues above have a single group.
  Future<List<TeamStanding>> getStandings({
    required int leagueId,
    required int season,
  }) async {
    final body = await _get('/standings', query: {
      'league': leagueId,
      'season': season,
    });
    final response = (body['response'] as List?) ?? const [];
    if (response.isEmpty) return const [];

    final league = (response.first as Map<String, dynamic>)['league']
        as Map<String, dynamic>?;
    final groups = (league?['standings'] as List?) ?? const [];
    if (groups.isEmpty) return const [];

    final group = (groups.first as List?) ?? const [];
    return group
        .map((e) => TeamStanding.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fixtures for a league and/or team in a season. Use `last`/`next` to fetch
  /// only recent results or upcoming matches; omit both for the full season.
  Future<List<Fixture>> getFixtures({
    required int season,
    int? leagueId,
    int? teamId,
    int? last,
    int? next,
  }) async {
    final query = <String, dynamic>{'season': season};
    if (leagueId != null) query['league'] = leagueId;
    if (teamId != null) query['team'] = teamId;
    if (last != null) query['last'] = last;
    if (next != null) query['next'] = next;

    final body = await _get('/fixtures', query: query);
    final response = (body['response'] as List?) ?? const [];
    return response
        .map((e) => Fixture.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (!hasKey) {
      throw const ApiException(
        'No API key set. Add it in Settings to load data.',
        isMissingKey: true,
      );
    }
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Unexpected response from the server.');
      }
      _throwIfApiErrors(data['errors']);
      return data;
    } on DioException catch (e) {
      throw ApiException(_mapDioError(e));
    }
  }

  /// API-Football reports problems in an `errors` field: an empty list `[]`
  /// when fine, or a populated map/list when something is wrong.
  void _throwIfApiErrors(Object? errors) {
    if (errors is Map && errors.isNotEmpty) {
      final message = errors.values.join(' ');
      throw ApiException(
        message.isEmpty ? 'The API rejected the request.' : message,
      );
    }
    if (errors is List && errors.isNotEmpty) {
      throw ApiException(errors.join(' '));
    }
  }

  void _captureRateLimit(Headers headers) {
    int? readInt(String name) {
      final value = headers.value(name);
      return value == null ? null : int.tryParse(value);
    }

    onRateLimit?.call(
      RateLimitInfo(
        remainingToday: readInt('x-ratelimit-requests-remaining'),
        dailyLimit: readInt('x-ratelimit-requests-limit'),
        remainingMinute: readInt('X-RateLimit-Remaining'),
        minuteLimit: readInt('X-RateLimit-Limit'),
        updatedAt: DateTime.now(),
      ),
    );
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
