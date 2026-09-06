import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('clearAll drops every cached API response, including the catalogue',
      () async {
    SharedPreferences.setMockInitialValues({
      'standings_4328_2024-2025': '{"ts":1,"data":[]}',
      'season_events_4335': '{"ts":1,"data":[]}',
      'team_events_40': '{"ts":1,"data":[]}',
      'stats_34': '{"ts":1,"data":[]}',
      // Catalogue caches written by the Settings screen. The free key caps
      // list endpoints (50 countries / 5 leagues), so these must be wiped on
      // an API-key change too.
      'catalog_countries_v3': '{"ts":1,"data":["England"]}',
      'catalog_leagues_v2_England': '{"ts":1,"data":[]}',
      // App state that must survive a key change.
      'followed_leagues_v2': '[]',
      'unrelated': 'keep me',
    });

    final prefs = await SharedPreferences.getInstance();
    await CacheStore(prefs).clearAll();

    expect(prefs.getKeys(), {'followed_leagues_v2', 'unrelated'});
  });

  test('writeJson/readJson round-trips data with a timestamp', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = CacheStore(prefs);

    await cache.writeJson('key', ['England', 'Spain']);
    final entry = cache.readJson('key');

    expect(entry, isNotNull);
    expect(entry!.data, ['England', 'Spain']);
    expect(entry.isFresh(const Duration(days: 1)), isTrue);
  });
}
