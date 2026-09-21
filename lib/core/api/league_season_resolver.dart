import '../../models/league.dart' show apiSeason;
import '../storage/cache_store.dart';
import 'football_api_client.dart';

/// Resolves the season string TheSportsDB indexes a league's data under.
///
/// European "winter" leagues use split years (`2025-2026`), while calendar-year
/// leagues — Allsvenskan, Eliteserien, … — run over a single year (`2026`).
/// Asking in the wrong format yields an empty body or even bogus tables, so the
/// format is discovered from the league's declared `strCurrentSeason`
/// (`lookupleague.php`) and cached. The split-year format remains the fallback
/// whenever that declaration is unavailable (offline, missing on the API).
class LeagueSeasonResolver {
  LeagueSeasonResolver({required this.client, required this.cache});

  /// A league's season format never changes, so a stale copy is harmless.
  static const _ttl = Duration(days: 7);

  final FootballApiClient client;
  final CacheStore cache;

  /// Whether [leagueId] indexes its seasons as `YYYY-YYYY` (as opposed to
  /// single calendar years). Split years are assumed while nothing better is
  /// known.
  Future<bool> usesSplitYears(int leagueId) async {
    final declared = await _declaredCurrentSeason(leagueId);
    return !isCalendarYearFormat(declared);
  }

  /// The API season string to request for the picker's [startYear].
  Future<String> forStartYear({
    required int leagueId,
    required int startYear,
  }) async {
    final declared = await _declaredCurrentSeason(leagueId);
    return isCalendarYearFormat(declared) ? '$startYear' : apiSeason(startYear);
  }

  Future<String?> _declaredCurrentSeason(int leagueId) async {
    final key = 'league_season_$leagueId';
    final cached = cache.readJson(key);
    if (cached != null && cached.isFresh(_ttl)) {
      return _season(cached.data);
    }
    try {
      final current = await client.getLeagueCurrentSeason(leagueId: leagueId);
      // Cache the empty result too, so a league without a declaration doesn't
      // re-query on every screen open.
      await cache.writeJson(key, current ?? '');
      return current;
    } catch (_) {
      // Offline / rate-limited: use any cached copy (even stale) if we have
      // one, otherwise let the caller fall back to the split-year guess.
      return _season(cached?.data);
    }
  }

  static String? _season(Object? data) {
    if (data is! String) return null;
    final season = data.trim();
    return season.isEmpty ? null : season;
  }
}

/// True when [declaredCurrentSeason] shows the league runs on single calendar
/// years (e.g. `"2026"`) rather than split seasons (`"2026-2027"`).
bool isCalendarYearFormat(String? declaredCurrentSeason) {
  final season = declaredCurrentSeason?.trim() ?? '';
  return RegExp(r'^\d{4}$').hasMatch(season);
}
