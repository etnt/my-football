import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/football_api_client.dart';
import '../core/storage/secure_key_store.dart';
import '../models/rate_limit_info.dart';

/// Provides the initialised [SharedPreferences]. Overridden in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final secureKeyStoreProvider =
    Provider<SecureKeyStore>((ref) => SecureKeyStore());

/// Latest rate-limit snapshot, updated by the API client on every response.
final rateLimitProvider =
    NotifierProvider<RateLimitNotifier, RateLimitInfo?>(RateLimitNotifier.new);

class RateLimitNotifier extends Notifier<RateLimitInfo?> {
  @override
  RateLimitInfo? build() => null;

  void update(RateLimitInfo info) => state = info;
}

/// The current API key (loaded from secure storage). `null` means "not set".
final apiKeyProvider =
    AsyncNotifierProvider<ApiKeyNotifier, String?>(ApiKeyNotifier.new);

class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(secureKeyStoreProvider).read();

  Future<void> setKey(String key) async {
    final trimmed = key.trim();
    await ref.read(secureKeyStoreProvider).save(trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(secureKeyStoreProvider).clear();
    state = const AsyncData(null);
  }
}

/// API client rebuilt whenever the key changes; forwards rate-limit updates.
final footballApiClientProvider = Provider<FootballApiClient>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  final client = FootballApiClient(
    apiKey: key,
    onRateLimit: (info) => ref.read(rateLimitProvider.notifier).update(info),
  );
  ref.onDispose(client.close);
  return client;
});
