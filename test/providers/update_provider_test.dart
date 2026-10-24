import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/config/app_version.dart';
import 'package:my_football/providers/update_provider.dart';

void main() {
  test('default checker targets the etnt/my-football releases feed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final checker = container.read(releaseCheckerProvider);

    expect(checker.owner, kReleaseOwner);
    expect(checker.repo, kReleaseRepo);
    expect(checker.owner, 'etnt');
    expect(checker.repo, 'my-football');
    // Test binaries get the 'dev' sentinel; ReleaseChecker must skip its
    // network call for it.
    expect(checker.currentVersion, appVersion);
    expect(checker.currentVersion, 'dev');
  });
}
