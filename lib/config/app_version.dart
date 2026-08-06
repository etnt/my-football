/// App version injected at build time via `--dart-define=APP_VERSION=...`
/// (set to the git tag in CI). Falls back to 'dev' for local/debug builds.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
