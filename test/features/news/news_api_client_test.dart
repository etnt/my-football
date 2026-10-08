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

NewsApiClient _client(_Adapter adapter) => NewsApiClient(
  dio: Dio(
    BaseOptions(
      baseUrl: 'https://gnews.test',
      validateStatus: (code) => code != null && code < 500,
    ),
  )..httpClientAdapter = adapter,
);

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
