/// A compact relative timestamp for a news item.
String timeAgo(DateTime value, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final weeks = difference.inDays ~/ 7;
  return '${weeks}w ago';
}
