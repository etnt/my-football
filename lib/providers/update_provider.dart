import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_version.dart';

/// GitHub account that publishes My Football releases.
const kReleaseOwner = 'etnt';

/// GitHub repository My Football releases are published to.
const kReleaseRepo = 'my-football';

/// Checks the My Football GitHub Releases feed for a newer app version.
/// `main()` overrides this with a persistent check store; tests can inject a
/// fake checker without reaching the network.
final releaseCheckerProvider = Provider<ReleaseChecker>((ref) {
  return ReleaseChecker(
    owner: kReleaseOwner,
    repo: kReleaseRepo,
    currentVersion: appVersion,
  );
});
