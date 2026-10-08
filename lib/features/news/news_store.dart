import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'news_item.dart';

/// Stores cleaned article fragments separately for each league.
class NewsStore {
  NewsStore(this._prefs);

  static const keyPrefix = 'news_items_';
  static Future<void> _mutationQueue = Future<void>.value();

  final SharedPreferences _prefs;

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  String _key(int leagueId) => '$keyPrefix$leagueId';

  Future<List<NewsItem>> load(int leagueId) async {
    final raw = _prefs.getString(_key(leagueId));
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(NewsItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> replaceAll(int leagueId, List<NewsItem> items) async {
    await _serialize(() => _replaceAllNow(leagueId, items));
  }

  /// Writes only if the refresh is still current when its queued write runs.
  /// Mutations share a queue with [clearAll], so a key change cannot clear the
  /// cache and then have an already-started stale write repopulate it.
  Future<bool> replaceAllIfCurrent(
    int leagueId,
    List<NewsItem> items, {
    required bool Function() isCurrent,
  }) => _serialize(() async {
    if (!isCurrent()) return false;
    await _replaceAllNow(leagueId, items);
    return true;
  });

  Future<void> _replaceAllNow(int leagueId, List<NewsItem> items) async {
    await _prefs.setString(
      _key(leagueId),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> pruneOlderThan(int leagueId, DateTime cutoff) =>
      _serialize(() async {
        await _pruneLeagueNow(leagueId, cutoff);
      });

  /// Prunes every persisted league cache after an age-setting change.
  Future<void> pruneAllOlderThan(DateTime cutoff) => _serialize(() async {
    final leagueIds = _prefs
        .getKeys()
        .where((key) => key.startsWith(keyPrefix))
        .map((key) => int.tryParse(key.substring(keyPrefix.length)))
        .whereType<int>()
        .toSet();
    for (final leagueId in leagueIds) {
      await _pruneLeagueNow(leagueId, cutoff);
    }
  });

  Future<void> _pruneLeagueNow(int leagueId, DateTime cutoff) async {
    final items = await load(leagueId);
    final kept = items
        .where((item) => !item.publishedAt.isBefore(cutoff))
        .toList();
    if (kept.length != items.length) {
      await _replaceAllNow(leagueId, kept);
    }
  }

  /// Removes all cached article fragments when the user's GNews key changes.
  static Future<void> clearAll(SharedPreferences prefs) => _serialize(() async {
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(keyPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  });
}
