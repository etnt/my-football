import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/lineup_player.dart';

/// Fetches a match's line-up with a local cache. Populated line-ups barely
/// change after kick-off (7 days); empty ones may be backfilled by the
/// provider later, so they re-check sooner (6 hours).
class LineupRepository {
  LineupRepository({required this.client, required this.cache});

  static const _ttl = Duration(days: 7);
  static const _emptyTtl = Duration(hours: 6);

  final FootballApiClient client;
  final CacheStore cache;

  Future<List<LineupPlayer>> getLineup({
    required int eventId,
    bool forceRefresh = false,
  }) async {
    final key = 'lineup_$eventId';
    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.data is List) {
        final players = _decode(cached.data);
        if (cached.isFresh(players.isEmpty ? _emptyTtl : _ttl)) {
          return players;
        }
      }
    }

    try {
      final fresh = await client.getEventLineup(eventId: eventId);
      await cache.writeJson(key, fresh.map((p) => p.toJson()).toList());
      return fresh;
    } catch (_) {
      final cached = cache.readJson(key);
      if (cached != null) return _decode(cached.data);
      rethrow;
    }
  }

  List<LineupPlayer> _decode(Object? data) => (data as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(LineupPlayer.fromJson)
          .whereType<LineupPlayer>()
          .toList() ??
      const [];
}
