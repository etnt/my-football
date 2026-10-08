import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/news/news_item.dart';
import 'package:my_football/features/news/news_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

NewsItem _item(String title, DateTime publishedAt) => NewsItem(
  title: title,
  description: 'Details',
  sourceName: 'Example',
  url: 'https://example.com/$title',
  publishedAt: publishedAt,
);

void main() {
  late SharedPreferences prefs;
  late NewsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = NewsStore(prefs);
  });

  test('round-trips per-league fragments', () async {
    final item = _item('headline', DateTime.utc(2026, 9, 2));
    await store.replaceAll(4328, [item]);

    final loaded = await store.load(4328);
    expect(loaded.single.toJson(), item.toJson());
    expect(await store.load(4335), isEmpty);
  });

  test('corrupt payload returns an empty list', () async {
    await prefs.setString('news_items_4328', '{broken');
    expect(await store.load(4328), isEmpty);
  });

  test('prunes headlines older than cutoff', () async {
    final cutoff = DateTime.utc(2026, 9, 2);
    await store.replaceAll(4328, [
      _item('old', cutoff.subtract(const Duration(seconds: 1))),
      _item('fresh', cutoff),
    ]);

    await store.pruneOlderThan(4328, cutoff);

    expect((await store.load(4328)).map((item) => item.title), ['fresh']);
  });

  test('prunes every league cache after the max-age setting changes', () async {
    final cutoff = DateTime.utc(2026, 9, 2);
    await store.replaceAll(4328, [
      _item('old A', cutoff.subtract(const Duration(seconds: 1))),
      _item('fresh A', cutoff),
    ]);
    await store.replaceAll(4335, [
      _item('old B', cutoff.subtract(const Duration(days: 2))),
      _item('fresh B', cutoff),
    ]);

    await store.pruneAllOlderThan(cutoff);

    expect((await store.load(4328)).map((item) => item.title), ['fresh A']);
    expect((await store.load(4335)).map((item) => item.title), ['fresh B']);
  });

  test('queued stale writes cannot repopulate a cleared cache', () async {
    final stale = _item('stale', DateTime.utc(2026));
    final clear = NewsStore.clearAll(prefs);
    final write = store.replaceAllIfCurrent(4328, [
      stale,
    ], isCurrent: () => false);

    await Future.wait([clear, write]);

    expect(await store.load(4328), isEmpty);
  });

  test(
    'clearAll removes every league cache and leaves other preferences',
    () async {
      await store.replaceAll(4328, [_item('one', DateTime.utc(2026))]);
      await store.replaceAll(4335, [_item('two', DateTime.utc(2026))]);
      await prefs.setString('news_api_key', 'secret');
      await NewsStore.clearAll(prefs);

      expect(await store.load(4328), isEmpty);
      expect(await store.load(4335), isEmpty);
      expect(prefs.getString('news_api_key'), 'secret');
    },
  );
}
