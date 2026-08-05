/// Thrown for any API-level problem, with a message safe to show the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.isMissingKey = false});

  final String message;

  /// True when the failure is simply that no API key is configured yet.
  final bool isMissingKey;

  @override
  String toString() => message;
}
