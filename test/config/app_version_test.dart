import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/config/app_version.dart';

void main() {
  test('appVersion falls back to the dev sentinel without a dart-define', () {
    // Test binaries are compiled without --dart-define=APP_VERSION, so the
    // value must be the 'dev' sentinel that makes ReleaseChecker skip the
    // update check.
    expect(appVersion, 'dev');
  });
}
