import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/news/news_item.dart';
import 'package:my_football/features/news/news_providers.dart';
import 'package:my_football/features/news/news_view.dart';

class _FixedNewsController extends NewsController {
  _FixedNewsController(this.items, {this.refreshCompletion});
  final List<NewsItem> items;
  final Completer<void>? refreshCompletion;
  int refreshCalls = 0;

  @override
  Future<List<NewsItem>> build() async => items;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    ref.read(newsRefreshStatusProvider.notifier).state = NewsRefreshStatus(
      scope: ref.read(newsRefreshScopeProvider),
      inFlight: true,
    );
    await refreshCompletion?.future;
    ref.read(newsRefreshStatusProvider.notifier).state = NewsRefreshStatus(
      scope: ref.read(newsRefreshScopeProvider),
    );
  }
}

Widget _host({
  required List<NewsItem> items,
  required bool needsKey,
  String? refreshError,
  _FixedNewsController? controller,
}) => ProviderScope(
  overrides: [
    newsProvider.overrideWith(() => controller ?? _FixedNewsController(items)),
    newsNeedsKeyProvider.overrideWithValue(needsKey),
    newsRefreshScopeProvider.overrideWithValue('test-scope'),
    if (refreshError != null)
      newsRefreshErrorProvider.overrideWith((ref) => refreshError),
  ],
  child: const MaterialApp(home: Scaffold(body: NewsView())),
);

void main() {
  final item = NewsItem(
    title: 'A headline',
    description: 'The full summary appears when expanded.',
    sourceName: 'Example News',
    url: 'https://example.com/news',
    publishedAt: DateTime.now().toUtc(),
  );

  testWidgets('shows a headline collapsed and the description when expanded', (
    tester,
  ) async {
    await tester.pumpWidget(_host(items: [item], needsKey: false));
    await tester.pumpAndSettle();

    expect(find.text('A headline'), findsOneWidget);
    expect(find.text('The full summary appears when expanded.'), findsNothing);
    await tester.tap(find.text('A headline'));
    await tester.pumpAndSettle();
    expect(
      find.text('The full summary appears when expanded.'),
      findsOneWidget,
    );
    expect(find.text('Read full article on Example News'), findsOneWidget);
  });

  testWidgets('shows a Settings call to action when the key is missing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(items: [], needsKey: true));
    await tester.pumpAndSettle();

    expect(find.text('Add a News API key in Settings'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('shows refresh errors without hiding cached headlines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        items: [item],
        needsKey: false,
        refreshError: 'GNews quota exceeded',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not refresh headlines'), findsOneWidget);
    expect(find.text('GNews quota exceeded'), findsOneWidget);
    expect(find.text('A headline'), findsOneWidget);
    expect(find.byTooltip('Retry refresh'), findsOneWidget);
  });

  testWidgets('retry button invokes refresh and disables while it is running', (
    tester,
  ) async {
    final completion = Completer<void>();
    final controller = _FixedNewsController([
      item,
    ], refreshCompletion: completion);
    await tester.pumpWidget(
      _host(
        items: [item],
        needsKey: false,
        refreshError: 'GNews quota exceeded',
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Retry refresh'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
    final retryButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Retry refresh',
    );
    expect(tester.widget<IconButton>(retryButton).onPressed, isNull);
    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(retryButton).onPressed, isNotNull);
  });

  testWidgets('asks the user to refresh when there are no cached headlines', (
    tester,
  ) async {
    await tester.pumpWidget(_host(items: [], needsKey: false));
    await tester.pumpAndSettle();

    expect(
      find.text('Pull down to refresh headlines for this league.'),
      findsOneWidget,
    );
    expect(find.text('Powered by GNews'), findsOneWidget);
  });
}
