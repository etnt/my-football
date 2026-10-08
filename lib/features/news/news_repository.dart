import '../../models/league.dart';
import 'news_api_client.dart';
import 'news_item.dart';
import 'news_store.dart';

/// Fetch-on-refresh repository. Opening News always reads the local store.
class NewsRepository {
  const NewsRepository({required this.client, required this.store});

  final NewsApiClient client;
  final NewsStore store;

  Future<List<NewsItem>> load(int leagueId, {int? maxAgeDays}) async {
    if (maxAgeDays != null) {
      final cutoff = DateTime.now().toUtc().subtract(
        Duration(days: maxAgeDays),
      );
      await store.pruneOlderThan(leagueId, cutoff);
    }
    return store.load(leagueId);
  }

  Future<List<NewsItem>> refresh({
    required League league,
    required String apiKey,
    required int maxAgeDays,
    bool Function()? isCurrent,
  }) async {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(Duration(days: maxAgeDays));
    final fetched = await client.searchLeagueNews(league.name, apiKey);
    final recent =
        fetched.where((item) => !item.publishedAt.isBefore(cutoff)).toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    // A key or league change can make an in-flight response obsolete. Check
    // inside the store's serialized mutation queue, so a cache clear cannot
    // race with a write that passed its stale-result check before the clear.
    await store.replaceAllIfCurrent(
      league.id,
      recent,
      isCurrent: isCurrent ?? () => true,
    );
    return recent;
  }
}
