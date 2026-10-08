import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/news/news_api_client.dart';
import 'package:my_football/features/news/news_item.dart';
import 'package:my_football/features/news/news_providers.dart';
import 'package:my_football/features/news/news_repository.dart';
import 'package:my_football/features/news/news_store.dart';
import 'package:my_football/models/league.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:my_football/features/standings/standings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedApiKeyNotifier extends NewsApiKeyNotifier {
  @override
  Future<String?> build() async => 'test-key';
}

class _MutableApiKeyNotifier extends NewsApiKeyNotifier {
  @override
  Future<String?> build() async => 'test-key';

  void changeKey(String key) => state = AsyncData(key);
}

class _FailingRepository extends NewsRepository {
  _FailingRepository(NewsItem cached)
    : _cached = cached,
      super(
        client: NewsApiClient(dio: Dio()),
        store: NewsStore(_prefs),
      );

  static late SharedPreferences _prefs;
  final NewsItem _cached;

  @override
  Future<List<NewsItem>> load(int leagueId, {int? maxAgeDays}) async => [
    _cached,
  ];

  @override
  Future<List<NewsItem>> refresh({
    required League league,
    required String apiKey,
    required int maxAgeDays,
    bool Function()? isCurrent,
  }) async => throw const NewsApiException('GNews quota exceeded');
}

class _ReloadRepository extends NewsRepository {
  _ReloadRepository(this.cached, {this.failInitialLoad = false})
    : super(
        client: NewsApiClient(dio: Dio()),
        store: NewsStore(_prefs),
      );

  static late SharedPreferences _prefs;
  final NewsItem cached;
  final bool failInitialLoad;
  final Completer<List<NewsItem>> initialLoad = Completer<List<NewsItem>>();
  bool refreshFailed = false;

  @override
  Future<List<NewsItem>> load(int leagueId, {int? maxAgeDays}) {
    if (refreshFailed) return Future.value([cached]);
    if (failInitialLoad) throw StateError('Saved news could not load');
    return initialLoad.future;
  }

  @override
  Future<List<NewsItem>> refresh({
    required League league,
    required String apiKey,
    required int maxAgeDays,
    bool Function()? isCurrent,
  }) async {
    refreshFailed = true;
    throw const NewsApiException('GNews quota exceeded');
  }
}

class _ControlledRepository extends NewsRepository {
  _ControlledRepository()
    : super(
        client: NewsApiClient(dio: Dio()),
        store: NewsStore(_prefs),
      );

  static late SharedPreferences _prefs;
  final refreshes =
      <({League league, String apiKey, Completer<List<NewsItem>> result})>[];

  @override
  Future<List<NewsItem>> load(int leagueId, {int? maxAgeDays}) async => [
    _item('Loaded $leagueId', 'https://example.com/$leagueId'),
  ];

  @override
  Future<List<NewsItem>> refresh({
    required League league,
    required String apiKey,
    required int maxAgeDays,
    bool Function()? isCurrent,
  }) {
    final completer = Completer<List<NewsItem>>();
    refreshes.add((league: league, apiKey: apiKey, result: completer));
    return completer.future;
  }
}

NewsItem _item(String title, String url) => NewsItem(
  title: title,
  description: 'Saved story',
  sourceName: 'Example',
  url: url,
  publishedAt: DateTime.now().toUtc(),
);

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    _FailingRepository._prefs = prefs;
    _ReloadRepository._prefs = prefs;
    _ControlledRepository._prefs = prefs;
  });

  ProviderContainer makeContainer({
    required NewsRepository repository,
    League? initialLeague,
    NewsApiKeyNotifier Function()? apiKeyNotifier,
  }) {
    final container = ProviderContainer(
      overrides: [
        newsApiKeyProvider.overrideWith(
          apiKeyNotifier ?? _FixedApiKeyNotifier.new,
        ),
        newsRepositoryProvider.overrideWithValue(repository),
        selectedLeagueProvider.overrideWith(
          (ref) => initialLeague ?? League.premierLeague,
        ),
        newsMaxAgeDaysProvider.overrideWith(
          (ref) => NewsMaxAgeDaysNotifier(prefs, NewsStore(prefs)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final newsSubscription = container.listen(newsProvider, (_, _) {});
    final errorSubscription = container.listen(
      newsRefreshErrorProvider,
      (_, _) {},
    );
    final inFlightSubscription = container.listen(
      newsRefreshInFlightProvider,
      (_, _) {},
    );
    addTearDown(newsSubscription.close);
    addTearDown(errorSubscription.close);
    addTearDown(inFlightSubscription.close);
    return container;
  }

  test('changing max age persists it and prunes every league cache', () async {
    final store = NewsStore(prefs);
    final now = DateTime.now().toUtc();
    NewsItem oldItem(String title, String url) => NewsItem(
      title: title,
      description: '',
      sourceName: 'Example',
      url: url,
      publishedAt: now.subtract(const Duration(days: 4)),
    );
    await store.replaceAll(League.premierLeague.id, [
      oldItem('Old A', 'https://example.com/old-a'),
    ]);
    await store.replaceAll(League.laLiga.id, [
      oldItem('Old B', 'https://example.com/old-b'),
    ]);
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await container.read(newsMaxAgeDaysProvider.notifier).setDays(3);

    expect(prefs.getInt('news_max_age_days'), 3);
    expect(await store.load(League.premierLeague.id), isEmpty);
    expect(await store.load(League.laLiga.id), isEmpty);
  });

  test(
    'failed refresh reloads cached headlines and exposes an error',
    () async {
      final cached = _item('Cached headline', 'https://example.com/cached');
      final container = makeContainer(repository: _FailingRepository(cached));
      await container.read(newsApiKeyProvider.future);
      await container.read(newsProvider.future);

      await container.read(newsProvider.notifier).refresh();

      expect(
        container.read(newsProvider).valueOrNull?.single.title,
        cached.title,
      );
      expect(container.read(newsRefreshErrorProvider), 'GNews quota exceeded');
    },
  );

  test(
    'refresh failure reloads stored headlines while initial load is pending',
    () async {
      final cached = _item('Stored headline', 'https://example.com/stored');
      final repository = _ReloadRepository(cached);
      final container = makeContainer(repository: repository);
      await container.read(newsApiKeyProvider.future);
      expect(container.read(newsProvider).isLoading, isTrue);

      await container.read(newsProvider.notifier).refresh();

      expect(
        container.read(newsProvider).valueOrNull?.single.title,
        cached.title,
      );
      repository.initialLoad.complete([cached]);
    },
  );

  test(
    'refresh failure reloads stored headlines after initial load error',
    () async {
      final cached = _item('Stored headline', 'https://example.com/stored');
      final repository = _ReloadRepository(cached, failInitialLoad: true);
      final container = makeContainer(repository: repository);
      await container.read(newsApiKeyProvider.future);
      await expectLater(container.read(newsProvider.future), throwsStateError);

      await container.read(newsProvider.notifier).refresh();

      expect(
        container.read(newsProvider).valueOrNull?.single.title,
        cached.title,
      );
    },
  );

  test('successful refresh clears a prior refresh error', () async {
    final refreshed = _item('Fresh headline', 'https://example.com/fresh');
    final repository = _ControlledRepository();
    final container = makeContainer(repository: repository);
    await container.read(newsApiKeyProvider.future);
    await container.read(newsProvider.future);

    final failedRefresh = container.read(newsProvider.notifier).refresh();
    repository.refreshes[0].result.completeError(
      const NewsApiException('Old error'),
    );
    await failedRefresh;
    expect(container.read(newsRefreshErrorProvider), 'Old error');

    final successfulRefresh = container.read(newsProvider.notifier).refresh();
    expect(container.read(newsRefreshErrorProvider), isNull);
    repository.refreshes[1].result.complete([refreshed]);
    await successfulRefresh;

    expect(
      container.read(newsProvider).valueOrNull?.single.title,
      refreshed.title,
    );
    expect(container.read(newsRefreshErrorProvider), isNull);
  });

  test(
    'league switch prevents an old refresh from writing current state',
    () async {
      final repository = _ControlledRepository();
      final container = makeContainer(repository: repository);
      await container.read(newsApiKeyProvider.future);
      await container.read(newsProvider.future);

      final refresh = container.read(newsProvider.notifier).refresh();
      expect(repository.refreshes.single.league.id, League.premierLeague.id);
      container.read(selectedLeagueProvider.notifier).state = League.laLiga;
      await container.read(newsProvider.future);
      repository.refreshes.single.result.complete([
        _item('Stale headline', 'https://example.com/stale'),
      ]);
      await refresh;

      expect(
        container.read(newsProvider).valueOrNull?.single.title,
        'Loaded ${League.laLiga.id}',
      );
      expect(container.read(newsRefreshErrorProvider), isNull);
    },
  );

  test('A to B to A keeps t3 in flight when stale t1 completes', () async {
    final repository = _ControlledRepository();
    final container = makeContainer(repository: repository);
    await container.read(newsApiKeyProvider.future);
    await container.read(newsProvider.future);

    // t1 starts in A.
    final t1 = container.read(newsProvider.notifier).refresh();
    expect(repository.refreshes[0].league.id, League.premierLeague.id);

    // Switch to B and start t2 while t1 is still pending.
    container.read(selectedLeagueProvider.notifier).state = League.laLiga;
    await container.read(newsProvider.future);
    final t2 = container.read(newsProvider.notifier).refresh();
    expect(repository.refreshes[1].league.id, League.laLiga.id);

    // Return to A and start t3. Its status supersedes t1's old status.
    container.read(selectedLeagueProvider.notifier).state =
        League.premierLeague;
    await container.read(newsProvider.future);
    final t3 = container.read(newsProvider.notifier).refresh();
    expect(repository.refreshes[2].league.id, League.premierLeague.id);
    expect(container.read(newsRefreshInFlightProvider), isTrue);

    repository.refreshes[0].result.complete([
      _item('Stale t1 headline', 'https://example.com/stale-t1'),
    ]);
    await t1;

    expect(container.read(newsRefreshInFlightProvider), isTrue);
    expect(container.read(newsRefreshErrorProvider), isNull);

    repository.refreshes[2].result.complete([
      _item('Fresh t3 headline', 'https://example.com/fresh-t3'),
    ]);
    await t3;

    expect(container.read(newsRefreshInFlightProvider), isFalse);
    expect(
      container.read(newsProvider).valueOrNull?.single.title,
      'Fresh t3 headline',
    );

    repository.refreshes[1].result.complete([
      _item('Stale t2 headline', 'https://example.com/stale-t2'),
    ]);
    await t2;
  });

  test('API key change prevents an old refresh from writing state', () async {
    final repository = _ControlledRepository();
    final container = makeContainer(
      repository: repository,
      apiKeyNotifier: _MutableApiKeyNotifier.new,
    );
    await container.read(newsApiKeyProvider.future);
    await container.read(newsProvider.future);

    final refresh = container.read(newsProvider.notifier).refresh();
    final keyNotifier =
        container.read(newsApiKeyProvider.notifier) as _MutableApiKeyNotifier;
    keyNotifier.changeKey('new-key');
    await container.read(newsProvider.future);
    repository.refreshes.single.result.completeError(
      const NewsApiException('Stale error'),
    );
    await refresh;

    expect(
      container.read(newsProvider).valueOrNull?.single.title,
      'Loaded ${League.premierLeague.id}',
    );
    expect(container.read(newsRefreshErrorProvider), isNull);
  });
}
