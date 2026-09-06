import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cache_store.dart';
import '../../models/league.dart';
import '../../providers/app_providers.dart';

/// The country/league catalogue changes rarely, so cache it on-device for a
/// week to avoid repeated network calls (and quota use) when browsing Settings.
const _catalogTtl = Duration(days: 7);

/// All countries offered by TheSportsDB, cached on device. Falls back to any
/// cached copy (even if stale) when offline.
///
/// Note the `_v3` suffix: v2 (and older) caches could have been written while
/// the free key was active — the free key caps `all_countries.php` at 50
/// countries, so England and friends were simply absent. Bumping the key
/// ignores those stale entries immediately on app update; `CacheStore
/// .clearAll()` additionally wipes catalogue caches on every API-key change.
final countriesProvider = FutureProvider<List<String>>((ref) async {
  final cache = CacheStore(ref.watch(sharedPreferencesProvider));
  const key = 'catalog_countries_v3';

  final cached = cache.readJson(key);
  if (cached != null && cached.isFresh(_catalogTtl)) {
    return (cached.data as List).cast<String>();
  }

  try {
    final countries = await ref.watch(footballApiClientProvider).getCountries();
    await cache.writeJson(key, countries);
    return countries;
  } catch (_) {
    if (cached != null) return (cached.data as List).cast<String>();
    rethrow;
  }
});

/// Soccer leagues within a given country, cached on device.
///
/// Key carries a `_v2` suffix for the same reason as `catalog_countries_v3`:
/// free-key responses are capped (5 leagues) and must not bleed into a
/// Premium session.
final leaguesByCountryProvider =
    FutureProvider.family<List<League>, String>((ref, country) async {
  final cache = CacheStore(ref.watch(sharedPreferencesProvider));
  final key = 'catalog_leagues_v2_$country';

  List<League> decode(Object? data) => ((data as List?) ?? const [])
      .map((e) => League.fromJson(e as Map<String, dynamic>))
      .toList();

  final cached = cache.readJson(key);
  if (cached != null && cached.isFresh(_catalogTtl)) {
    return decode(cached.data);
  }

  try {
    final leagues =
        await ref.watch(footballApiClientProvider).getLeaguesByCountry(country);
    await cache.writeJson(key, leagues.map((l) => l.toJson()).toList());
    return leagues;
  } catch (_) {
    if (cached != null) return decode(cached.data);
    rethrow;
  }
});
