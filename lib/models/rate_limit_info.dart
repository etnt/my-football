/// Snapshot of API rate-limit state, parsed from response headers on every call.
class RateLimitInfo {
  const RateLimitInfo({
    this.remainingToday,
    this.dailyLimit,
    this.remainingMinute,
    this.minuteLimit,
    required this.updatedAt,
  });

  final int? remainingToday;
  final int? dailyLimit;
  final int? remainingMinute;
  final int? minuteLimit;
  final DateTime updatedAt;

  /// e.g. "87/100" for the daily counter, or "—/—" when unknown.
  String get dailyLabel =>
      '${remainingToday ?? '—'}/${dailyLimit ?? '—'}';
}
