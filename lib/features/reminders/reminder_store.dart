import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'match_reminder.dart';

/// Persists match reminders as a JSON list in [SharedPreferences].
///
/// Follows the same lightweight style as `CacheStore`: one string key holding
/// a JSON-encoded list, replaced wholesale on every change.
class ReminderStore {
  ReminderStore(this._prefs);

  static const _key = 'match_reminders';

  final SharedPreferences _prefs;

  /// All saved reminders. Returns an empty list on fresh storage or if the
  /// stored payload is corrupt (fail-safe: reminders are not critical data).
  Future<List<MatchReminder>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MatchReminder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Inserts [reminder], replacing any existing reminder for the same fixture.
  Future<void> upsert(MatchReminder reminder) async {
    final all = List.of(await load());
    all.removeWhere((r) => r.fixtureId == reminder.fixtureId);
    all.add(reminder);
    await _write(all);
  }

  /// Removes the reminder for [fixtureId] (a no-op when there is none).
  Future<void> remove(int fixtureId) async {
    final all = List.of(await load());
    all.removeWhere((r) => r.fixtureId == fixtureId);
    await _write(all);
  }

  /// Drops reminders whose match has already kicked off. Called on app start.
  Future<void> removeExpired() async {
    final all = await load();
    final kept = all.where((r) => !r.isExpired).toList();
    if (kept.length != all.length) await _write(kept);
  }

  /// The stored reminder for [fixtureId], or `null` when none exists.
  static MatchReminder? forFixture(List<MatchReminder> list, int fixtureId) {
    for (final reminder in list) {
      if (reminder.fixtureId == fixtureId) return reminder;
    }
    return null;
  }

  Future<void> _write(List<MatchReminder> reminders) {
    return _prefs.setString(
      _key,
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
  }
}
