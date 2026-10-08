import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/news/news_api_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.statusCode, this.body);
  final int statusCode;
  final String body;
  RequestOptions? request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _MultiPageAdapter implements HttpClientAdapter {
  _MultiPageAdapter(this.bodies, {this.statusCodes = const {}});

  final Map<int, String> bodies;
  final Map<int, int> statusCodes;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final page = options.queryParameters['page'] as int? ?? 1;
    return ResponseBody.fromString(
      bodies[page] ?? jsonEncode({'articles': []}),
      statusCodes[page] ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

NewsApiClient _client(HttpClientAdapter adapter) => NewsApiClient(
  dio: Dio(
    BaseOptions(
      baseUrl: 'https://gnews.test',
      validateStatus: (code) => code != null && code < 500,
    ),
  )..httpClientAdapter = adapter,
);

Map<String, dynamic> _article(
  int index, {
  String? url,
  DateTime? publishedAt,
}) => {
  'title': 'Headline $index',
  'description': 'Description $index',
  'source': {'name': 'Source'},
  'url': url ?? 'https://example.com/article-$index',
  'publishedAt': (publishedAt ?? DateTime.utc(2026, 9, 2, 12))
      .toIso8601String(),
};

String _body(Iterable<Map<String, dynamic>> articles) =>
    jsonEncode({'articles': articles.toList()});

void main() {
  test('decodes GNews articles and cleans residual HTML/entities', () async {
    final adapter = _Adapter(
      200,
      jsonEncode({
        'articles': [
          {
            'title': '<b>Big &amp; bold</b>',
            'description': 'A &lt;great&gt; goal',
            'source': {'name': 'The &quot;Paper&quot;'},
            'url': 'https://example.com/article',
            'publishedAt': '2026-09-02T12:00:00Z',
          },
        ],
      }),
    );
    final client = _client(adapter);
    final items = await client.searchLeagueNews('Premier League', 'key');

    expect(items.single.title, 'Big & bold');
    expect(items.single.description, 'A <great> goal');
    expect(items.single.sourceName, 'The "Paper"');
    expect(adapter.request?.queryParameters['q'], 'Premier League');
    expect(adapter.request?.queryParameters['token'], 'key');
    expect(adapter.request?.queryParameters['max'], 10);
    expect(adapter.request?.queryParameters['page'], 1);
    expect(adapter.request?.queryParameters['sortby'], 'publishedAt');
    client.close();
  });

  test('fetches multiple pages up to a short final page', () async {
    final adapter = _MultiPageAdapter({
      1: _body(List.generate(10, (index) => _article(index))),
      2: _body(List.generate(10, (index) => _article(index + 10))),
      3: _body(List.generate(3, (index) => _article(index + 20))),
    });
    final client = _client(adapter);

    final items = await client.searchLeagueNews('Premier League', 'key');

    expect(items, hasLength(23));
    expect(items.map((item) => item.url).toSet(), hasLength(23));
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests.map((request) => request.queryParameters['page']), [
      1,
      2,
      3,
    ]);
    expect(adapter.requests.last.queryParameters['page'], 3);
    client.close();
  });

  test('stops after a page with an empty articles list', () async {
    final adapter = _MultiPageAdapter({
      1: _body(List.generate(10, (index) => _article(index))),
      2: _body([]),
      3: _body([_article(30)]),
    });
    final client = _client(adapter);

    final items = await client.searchLeagueNews('Premier League', 'key');

    expect(items, hasLength(10));
    expect(adapter.requests, hasLength(2));
    client.close();
  });

  test('stops after a later page is entirely older than the cutoff', () async {
    final cutoff = DateTime.utc(2026, 9, 1);
    final adapter = _MultiPageAdapter({
      1: _body(List.generate(10, (index) => _article(index))),
      2: _body(
        List.generate(
          10,
          (index) =>
              _article(index + 10, publishedAt: DateTime.utc(2026, 8, 1)),
        ),
      ),
      3: _body([_article(30)]),
    });
    final client = _client(adapter);

    final items = await client.searchLeagueNews(
      'Premier League',
      'key',
      publishedBefore: cutoff,
    );

    expect(items, hasLength(20));
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.queryParameters['sortby'], 'publishedAt');
    client.close();
  });

  test('keeps earlier pages when a later page has a non-auth error', () async {
    for (final status in [403, 429]) {
      final adapter = _MultiPageAdapter(
        {
          1: _body(List.generate(10, (index) => _article(index))),
          2: '{"errors":["request rejected"]}',
        },
        statusCodes: {2: status},
      );
      final client = _client(adapter);

      final items = await client.searchLeagueNews('Premier League', 'key');

      expect(items, hasLength(10));
      expect(items.first.title, 'Headline 0');
      expect(adapter.requests, hasLength(2));
      client.close();
    }
  });

  test(
    'throws when a later page fails with an auth error and preserves status',
    () async {
      final adapter = _MultiPageAdapter(
        {
          1: _body(List.generate(10, (index) => _article(index))),
          2: '{"errors":["invalid token"]}',
        },
        statusCodes: {2: 401},
      );
      final client = _client(adapter);

      await expectLater(
        client.searchLeagueNews('Premier League', 'bad'),
        throwsA(
          isA<NewsApiException>().having(
            (error) => error.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(adapter.requests, hasLength(2));
      client.close();
    },
  );

  test('validateApiKey makes one request with max 1', () async {
    final adapter = _MultiPageAdapter({1: _body([])});
    final client = _client(adapter);

    await client.validateApiKey('key');

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, '/top-headlines');
    expect(adapter.requests.single.queryParameters['max'], 1);
    expect(
      adapter.requests.single.queryParameters.containsKey('page'),
      isFalse,
    );
    client.close();
  });

  test('converts GNews 4xx response to a typed error', () async {
    final client = _client(_Adapter(401, '{"errors":["invalid token"]}'));
    await expectLater(
      client.searchLeagueNews('Premier League', 'bad'),
      throwsA(
        isA<NewsApiException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    client.close();
  });
}
