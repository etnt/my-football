/// Account/quota information returned by the API-Football `/status` endpoint.
class AccountStatus {
  const AccountStatus({
    required this.plan,
    required this.requestsToday,
    required this.dailyLimit,
    required this.active,
  });

  final String plan;
  final int requestsToday;
  final int dailyLimit;
  final bool active;

  int get remainingToday => (dailyLimit - requestsToday).clamp(0, dailyLimit);

  factory AccountStatus.fromJson(Map<String, dynamic> json) {
    final subscription =
        (json['subscription'] as Map<String, dynamic>?) ?? const {};
    final requests = (json['requests'] as Map<String, dynamic>?) ?? const {};
    return AccountStatus(
      plan: (subscription['plan'] as String?) ?? 'Unknown',
      active: (subscription['active'] as bool?) ?? false,
      requestsToday: _asInt(requests['current']),
      dailyLimit: _asInt(requests['limit_day']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
