import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/settings_screen.dart';
import 'news_item.dart';
import 'news_providers.dart';
import 'time_ago.dart';

class NewsView extends ConsumerWidget {
  const NewsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(newsProvider);
    final needsKey = ref.watch(newsNeedsKeyProvider);
    final refreshError = ref.watch(newsRefreshErrorProvider);
    final refreshInFlight = ref.watch(newsRefreshInFlightProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(newsProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (needsKey)
            _EmptyMessage(
              icon: Icons.key_off_outlined,
              title: 'Add a News API key in Settings',
              detail:
                  'Add your free GNews key to load headlines for this league.',
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            )
          else ...[
            if (refreshError != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.sync_problem_outlined),
                  title: const Text('Could not refresh headlines'),
                  subtitle: Text(refreshError),
                  trailing: IconButton(
                    tooltip: 'Retry refresh',
                    onPressed: refreshInFlight
                        ? null
                        : () => ref.read(newsProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
            news.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _EmptyMessage(
                icon: Icons.error_outline,
                title: 'Could not load saved news',
                detail: error.toString(),
                action: TextButton.icon(
                  onPressed: () => ref.read(newsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyMessage(
                      icon: Icons.newspaper_outlined,
                      title: 'No headlines yet',
                      detail: 'Pull down to refresh headlines for this league.',
                    )
                  : _NewsList(items: items),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Powered by GNews',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsList extends StatelessWidget {
  const _NewsList({required this.items});

  final List<NewsItem> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items)
        Card(
          key: ValueKey(item.url),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: CircleAvatar(
              child: Text(
                item.sourceName.isEmpty
                    ? '?'
                    : item.sourceName.characters.first.toUpperCase(),
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (item.sourceName.isNotEmpty) item.sourceName,
                timeAgo(item.publishedAt),
              ].join(' · '),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.description.isNotEmpty) ...[
                Text(item.description),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: () => _openArticle(item),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  'Read full article on ${item.sourceName.isEmpty ? 'GNews' : item.sourceName}',
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Future<void> _openArticle(NewsItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      // A failed browser launch must not interrupt the app.
    }
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
    child: Column(
      children: [
        Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
