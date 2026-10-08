import 'package:dio/dio.dart';

import 'news_item.dart';

/// A readable API failure returned by GNews or the network layer.
class NewsApiException implements Exception {
  const NewsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Small injectable client for the GNews API.
class NewsApiClient {
  NewsApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://gnews.io/api/v4',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<List<NewsItem>> searchLeagueNews(
    String leagueName,
    String apiKey,
  ) async {
    final data = await _get('/search', {
      'q': leagueName,
      'lang': 'en',
      'max': 25,
      'token': apiKey,
    });
    final articles = data['articles'];
    if (articles is! List) return const [];
    return articles
        .whereType<Map<String, dynamic>>()
        .map((article) => NewsItem.fromJson(article))
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
  }

  /// Lightweight key check used by Settings. A valid response may contain no
  /// headlines; authentication success is what matters.
  Future<void> validateApiKey(String apiKey) async {
    await _get('/top-headlines', {
      'category': 'sports',
      'lang': 'en',
      'max': 1,
      'token': apiKey,
    });
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: query);
      final data = response.data;
      if ((response.statusCode ?? 500) >= 400) {
        final message = data is Map<String, dynamic>
            ? (data['errors']?.toString() ?? data['message']?.toString())
            : null;
        throw NewsApiException(
          message == null || message.isEmpty
              ? 'GNews rejected the request (HTTP ${response.statusCode}). Check the API key and try again.'
              : 'GNews: $message',
          statusCode: response.statusCode,
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const NewsApiException('GNews returned an unexpected response.');
      }
      return data;
    } on DioException catch (error) {
      throw NewsApiException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The news request timed out. Try again.',
        DioExceptionType.connectionError =>
          'Could not reach GNews. Check your connection.',
        _ => 'Could not load news: ${error.message ?? 'network error'}.',
      });
    }
  }

  void close() => _dio.close(force: true);
}
