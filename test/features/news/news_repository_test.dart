import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/news/news_api_client.dart';
import 'package:my_football/features/news/news_item.dart';
import 'package:my_football/features/news/news_repository.dart';
import 'package:my_football/features/news/news_store.dart';
import 'package:my_football/models/league.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late SharedPreferences prefs;
  late NewsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = NewsStore(prefs);
  });

  NewsRepository repository(_Adapter adapter) => NewsRepository(
    client: NewsApiClient(
      dio: Dio(
        BaseOptions(
          baseUrl: 'https://gnews.test',
          validateStatus: (code) => code != null && code < 500,
        ),
      )..httpClientAdapter = adapter,
    ),
    store: store,
  );

  test('filters stored headlines by configured max age on load', () async {
    final now = DateTime.now().toUtc();
    await store.replaceAll(League.premierLeague.id, [
      NewsItem(
        title: 'Fresh saved story',
        description: '',
        sourceName: 'Paper',
        url: 'https://example.com/fresh-saved',
        publishedAt: now.subtract(const Duration(hours: 3)),
      ),
      NewsItem(
        title: 'Expired saved story',
        description: '',
        sourceName: 'Paper',
        url: 'https://example.com/expired-saved',
        publishedAt: now.subtract(const Duration(days: 2)),
      ),
    ]);

    final items = await repository(
      _Adapter(200, '{"articles":[]}'),
    ).load(League.premierLeague.id, maxAgeDays: 1);

    expect(items.map((item) => item.title), ['Fresh saved story']);
    expect(
      (await store.load(League.premierLeague.id)).map((item) => item.title),
      ['Fresh saved story'],
    );
  });

  test('filters by configured max age and persists fresh items', () async {
    final now = DateTime.now().toUtc();
    final adapter = _Adapter(
      200,
      jsonEncode({
        'articles': [
          {
            'title': 'Recent',
            'description': 'desc',
            'source': {'name': 'Paper'},
            'url': 'https://example.com/new',
            'publishedAt': now
                .subtract(const Duration(hours: 3))
                .toIso8601String(),
          },
          {
            'title': 'Old',
            'source': {'name': 'Paper'},
            'url': 'https://example.com/old',
            'publishedAt': now
                .subtract(const Duration(days: 2))
                .toIso8601String(),
          },
        ],
      }),
    );
    final repo = repository(adapter);

    final items = await repo.refresh(
      league: League.premierLeague,
      apiKey: 'test-key',
      maxAgeDays: 1,
    );

    expect(items.map((item) => item.title), ['Recent']);
    expect(
      (await store.load(League.premierLeague.id)).map((item) => item.title),
      ['Recent'],
    );
  });

  test(
    'does not persist a response after its refresh scope becomes stale',
    () async {
      final prior = NewsItem(
        title: 'Prior',
        description: '',
        sourceName: 'Paper',
        url: 'https://example.com/prior',
        publishedAt: DateTime.now().toUtc(),
      );
      await store.replaceAll(League.premierLeague.id, [prior]);
      final now = DateTime.now().toUtc();
      final repo = repository(
        _Adapter(
          200,
          jsonEncode({
            'articles': [
              {
                'title': 'Stale response',
                'source': {'name': 'Paper'},
                'url': 'https://example.com/stale',
                'publishedAt': now.toIso8601String(),
              },
            ],
          }),
        ),
      );

      await repo.refresh(
        league: League.premierLeague,
        apiKey: 'test-key',
        maxAgeDays: 1,
        isCurrent: () => false,
      );

      expect((await store.load(League.premierLeague.id)).single.title, 'Prior');
    },
  );

  test('propagates API errors and does not replace stored content', () async {
    final prior = NewsItem(
      title: 'Prior',
      description: '',
      sourceName: 'Paper',
      url: 'https://example.com/prior',
      publishedAt: DateTime.now().toUtc(),
    );
    await store.replaceAll(League.premierLeague.id, [prior]);
    final repo = repository(_Adapter(429, '{"errors":["quota exceeded"]}'));

    await expectLater(
      repo.refresh(
        league: League.premierLeague,
        apiKey: 'test-key',
        maxAgeDays: 1,
      ),
      throwsA(isA<NewsApiException>()),
    );
    expect((await store.load(League.premierLeague.id)).single.title, 'Prior');
  });
}
