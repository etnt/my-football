/// A cleaned headline fragment stored for the News tab.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.description,
    required this.sourceName,
    required this.url,
    required this.publishedAt,
  });

  final String title;
  final String description;
  final String sourceName;
  final String url;
  final DateTime publishedAt;

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final sourceMap = source is Map<String, dynamic> ? source : const {};
    return NewsItem(
      title: cleanNewsText(json['title'] as String? ?? ''),
      description: cleanNewsText(json['description'] as String? ?? ''),
      sourceName: cleanNewsText(
        (json['sourceName'] as String?) ?? (sourceMap['name'] as String? ?? ''),
      ),
      url: (json['url'] as String? ?? '').trim(),
      publishedAt:
          DateTime.tryParse(json['publishedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': cleanNewsText(title),
    'description': cleanNewsText(description),
    'sourceName': cleanNewsText(sourceName),
    'url': url,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
  };
}

/// Removes residual markup and decodes common and numeric HTML entities.
String cleanNewsText(String value) {
  final plain = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return plain
      .replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (match) {
        final entity = match[1]!;
        const named = {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
          'ndash': '–',
          'mdash': '—',
          'rsquo': '’',
          'lsquo': '‘',
          'rdquo': '”',
          'ldquo': '“',
          'hellip': '…',
        };
        if (entity.startsWith('#x')) {
          return String.fromCharCode(
            int.tryParse(entity.substring(2), radix: 16) ?? 0xfffd,
          );
        }
        if (entity.startsWith('#')) {
          return String.fromCharCode(
            int.tryParse(entity.substring(1)) ?? 0xfffd,
          );
        }
        return named[entity] ?? match[0]!;
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
