import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../models/league.dart';

/// Whether we're showing recent results or upcoming matches.
enum FixturesMode { results, upcoming }

/// Fetches fixtures with a short TTL cache (matches change more often than a
/// full-season table). Falls back to any cached copy on failure.
class FixturesRepository {
  FixturesRepository({required this.client, required this.cache});

  static const _ttl = Duration(minutes: 30);
  static const _count = 20;

  final FootballApiClient client;
  final CacheStore cache;

  String _cacheKey(int leagueId, int season, FixturesMode mode) =>
      'fixtures_${leagueId}_${season}_${mode.name}';

  Future<List<Fixture>> getFixtures({
    required League league,
    required int season,
    required FixturesMode mode,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(league.id, season, mode);

    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.isFresh(_ttl)) {
        return _sort(_decode(cached.data), mode);
      }
    }

    try {
      final fresh = await client.getFixtures(
        leagueId: league.id,
        season: season,
        last: mode == FixturesMode.results ? _count : null,
        next: mode == FixturesMode.upcoming ? _count : null,
      );
      await cache.writeJson(key, fresh.map((e) => e.toJson()).toList());
      return _sort(fresh, mode);
    } catch (_) {
      final cached = cache.readJson(key);
      if (cached != null) return _sort(_decode(cached.data), mode);
      rethrow;
    }
  }

  List<Fixture> _decode(Object? data) {
    final list = (data as List?) ?? const [];
    return list
        .map((e) => Fixture.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<Fixture> _sort(List<Fixture> fixtures, FixturesMode mode) {
    final sorted = [...fixtures];
    sorted.sort((a, b) => a.dateUtc.compareTo(b.dateUtc));
    // Most recent result first; soonest upcoming first.
    if (mode == FixturesMode.results) {
      return sorted.reversed.toList();
    }
    return sorted;
  }
}
