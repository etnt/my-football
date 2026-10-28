# Developers

This guide covers the app architecture, local setup, device runs, tests, and release builds.

## How it works

Data comes from the [TheSportsDB](https://www.thesportsdb.com/) sports API. The
app talks to two endpoints:

- **v1 (free):** standings, season fixtures, and team events using the shared
  free key. No sign-up required.
- **v2 (premium):** live in-play scores, fuller team schedules, and per-match
  timelines, authenticated with a personal API key sent in the `X-API-KEY`
  header.

TheSportsDB has no top-scorer endpoint, so the **Player stats** leaderboards are
built on-device by aggregating each finished match's timeline (a single v2 call
per match yields scorers, assists and cards). To respect the premium rate
limit the build is throttled (~50 requests/min, well under the 100/min cap) and
backs off on HTTP 429. Because a finished match never changes, each match's
result is cached permanently — so the leaderboard is a one-time build that then
refreshes incrementally as new matches finish. The season schedule itself is
re-checked at most every ~6 hours (or immediately on pull-to-refresh), so newly
finished matches are picked up without re-fetching the ones already processed.

Network responses are cached in `shared_preferences` with a short TTL to reduce
requests and keep the UI responsive; the cache is cleared automatically when the
API key changes.

## News

The News tab searches GNews for the selected league when the user pulls to
refresh. It does not fetch on tab open. Users provide their own GNews API key in
Settings; it is stored in SharedPreferences on the device and is not part of
TheSportsDB Premium. Saved headlines are kept per league and age-filtered using
the `News max age` setting in Settings (1, 3, or 7 days; default 1 day).
Article links open in the platform in-app browser. No new package is needed.

## On-device AI recaps

Finished matches get a short recap at the top of the goals sheet. On supported
Android phones, Gemini Nano (the model built into the phone) writes the recap
in prose. Nothing is sent to a server. The design plan is in
[`plan/feature-ai-recaps-search-1.md`](plan/feature-ai-recaps-search-1.md).

### How it works

1. `FactSheet` (`lib/features/recap/fact_sheet.dart`) collects the match
   facts: teams, score, round, and (with a Premium key) goals and cards. If
   the timeline does not account for every goal, goals and cards are dropped
   and the facts are score-only.
2. `RecapBuilder` (`lib/features/recap/recap_builder.dart`) builds a plain
   template from the facts. If the facts are complete (the timeline accounts
   for every goal), it asks the model for a rewrite. The availability check and the generation share an 8-second
   timeout.
3. The model is reached through `AiService`. On Android this is
   `GeminiNanoService` (`lib/features/ai/gemini_nano_service.dart`), which
   talks over the `my_football/ai` method channel to
   `android/app/src/main/kotlin/.../GeminiNanoChannel.kt`. That class uses the
   ML Kit GenAI Prompt API (`com.google.mlkit:genai-prompt`, beta). Other
   platforms use `UnavailableAiService`.
4. The validator checks the model text (see below). Accepted text is cached
   under `recap_<fixtureId>_<promptVersion>`. Rejected or missing text is not
   cached, so the next open tries again.
5. In the UI, `Show recap` shows the AI text. Without it, `Show facts` shows the
   fact lines.

The Prompt API needs Android API 26, so `minSdk` is 26. Supported phones are
listed in the **Device support** section of
[Google's ML Kit GenAI page](https://developers.google.com/ml-kit/genai).

### The validator

Small models sometimes invent details: a wrong score, an extra goal, or a
player who was not in the match. `validateRecapText`
(`lib/features/ai/output_validator.dart`) compares the model text with the
fact sheet and rejects it if:

- it contains a **number** that is not in the facts (score, minute, round,
  date);
- it contains a **capitalised word** that is neither a team or player in the
  facts nor on the common-word allowlist (`_nameAllowlist`);
- it mentions **injuries, transfers, referees, suspensions, or VAR** that the
  facts do not mention;
- it is shorter than 60 or longer than 600 characters.

A rejected recap is dropped and the user sees the plain facts instead.

The name check cannot tell a sentence-opening word from an unknown name. If a
common word such as "Several" or "Round" causes false rejections, add it to
`_nameAllowlist` and cover it in `test/features/ai/output_validator_test.dart`.
Never add player or team names to the allowlist. Every rejection is logged
with the offending word, for example
`validateRecapText: rejected (unknownName: "Several")`.

If you change the prompt in `lib/features/ai/prompt_templates.dart`, bump
`recapPromptVersion` so cached recaps are regenerated.

### Debugging the model on a phone

- Log lines (`[AI recap] ...` and `validateRecapText: ...`) go to logcat in
  every build, including release builds:

  ```bash
  adb logcat | grep -E "AI recap|validateRecapText"
  ```

- To show the same log in the app, under the recap, build with:

  ```bash
  flutter run --dart-define=AI_DIAGNOSTICS=true
  ```

- To probe availability and generation speed at startup, run:

  ```bash
  flutter run --dart-define=AI_SPIKE=true
  ```

  The probe ([`lib/dev/ai_spike.dart`](lib/dev/ai_spike.dart)) logs
  `[AI spike]` lines.

- A GitHub release has a higher `versionCode` and a different signing key than
  a local build. To install a local build over it, uninstall the app first.
  That deletes the saved API keys.

### Release builds and R8

Flutter release builds run **R8**, which shrinks the app and renames classes.
Debug builds do not. Without keep rules, R8 broke ML Kit's internal component
lookup: `MlKitContext.get(SharedPrefManager.class)` returned `null`, and the
GenAI client threw a `NullPointerException` while it was being created. The
model then reported itself unavailable, so release builds never showed an AI
recap while debug builds worked.

The fix is [`android/app/proguard-rules.pro`](android/app/proguard-rules.pro),
which keeps the ML Kit classes and their component registrars. The Flutter
Gradle plugin applies this file to release builds automatically. Do not delete
it.

If a feature works in debug but not in release, suspect R8 first:

1. Build a local release and test it on a phone: `flutter build apk --release`.
2. Look up obfuscated class names from a stack trace in
   `build/app/outputs/mapping/release/mapping.txt`.
3. Add a `-keep` rule for the affected library to `proguard-rules.pro`.

## Project structure

The code follows a feature-first layout under `lib/`:

```
lib/
├─ main.dart, app.dart          # entry point and root widget
├─ config/                      # build-time config (e.g. app_version)
├─ core/
│  ├─ api/                      # TheSportsDB v1 & v2 clients, exceptions
│  └─ storage/                  # secure key store + TTL cache store
├─ models/                      # Fixture, League, TeamStanding, GoalEvent, CardEvent
├─ providers/                   # app-wide Riverpod providers (API key, clients)
├─ features/
│  ├─ home/                     # bottom-nav shell
│  ├─ standings/                # league table
│  ├─ fixtures/                 # results & upcoming, grouped by matchweek
│  ├─ live/                     # live scores (premium)
│  ├─ news/                     # GNews headlines, store and refresh UI
│  ├─ stats/                    # scorers, assists & cards leaderboards (premium)
│  ├─ team/                     # team detail & schedule
│  ├─ ai/                       # AiService, Gemini Nano channel, validator, log
│  ├─ recap/                    # match recaps: fact sheet, builder, UI
│  └─ settings/                 # API key entry & validation
└─ shared/widgets/              # reusable error / message views
```

Each feature groups its `view`, `repository`, and `providers` together.

## Tech stack

- **[Flutter](https://flutter.dev/) / Dart** — cross-platform UI.
- **[flutter_riverpod](https://riverpod.dev/)** — state management and
  dependency injection.
- **[dio](https://pub.dev/packages/dio)** — HTTP client for the TheSportsDB API.
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)** —
  encrypted on-device storage for the premium API key.
- **[shared_preferences](https://pub.dev/packages/shared_preferences)** —
  lightweight TTL response cache, News settings and saved headline fragments.
- **[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)** —
  local goal alerts while the Live tab is open.

## Getting started

Fetch dependencies:

```bash
flutter pub get
```

Run on a connected device or emulator:

```bash
flutter run                # auto-selects a device
flutter run -d <deviceId>  # target a specific device (see: flutter devices)
```

## Running on a physical Android phone

1. **Enable Developer options** on the phone: Settings → About phone → tap
   **Build number** seven times.
2. **Enable USB debugging**: Settings → System → Developer options → **USB
   debugging** on.
3. **Connect the phone to the computer** with a **data-capable** USB cable
   (charge-only cables will not work). Plug directly into the machine rather than
   through a hub or dock.
4. **Set the USB mode** on the phone to **File transfer / MTP** via the USB
   notification — some phones default to charge-only, which blocks the data
   connection.
5. **Authorize the computer**: unlock the phone and accept the *Allow USB
   debugging?* prompt (tick *Always allow from this computer* to skip it next
   time).
6. **Verify the device is detected**:

   ```bash
   # platform-tools ships with the Android SDK, e.g.
   #   macOS:  $HOME/Library/Android/sdk/platform-tools
   adb devices -l     # should list your phone with state "device"
   flutter devices    # should show the phone
   ```
7. **Build, install, and launch** on the phone:

   ```bash
   flutter run -d <deviceId>   # deviceId from `flutter devices`, e.g. 56041FDCH00CDN
   ```

   Flutter builds the debug APK, installs it, and starts a live debug session
   (hot reload with `r`, hot restart with `R`). The app also stays installed in
   the app drawer after you quit the session.

## Running on a physical iOS phone

Deploying to an iPhone requires a **Mac with Xcode** installed (plus its
command-line tools and CocoaPods).

1. **Sign in with an Apple ID in Xcode**: Xcode → Settings → Accounts → add your
   Apple ID. A free Apple ID works for on-device development (with a 7-day
   signing validity); a paid Apple Developer account removes that limit.
2. **Set the signing team** for the app. Either open the iOS project in Xcode:

   ```bash
   open ios/Runner.xcworkspace
   ```

   then select the **Runner** target → **Signing & Capabilities** → pick your
   **Team** and let Xcode manage signing. Xcode will assign a unique bundle
   identifier if the default is taken.
3. **Connect the iPhone** with a cable and **trust the computer**: on the phone,
   tap **Trust** on the *Trust This Computer?* prompt and enter your passcode.
4. **Enable Developer Mode** (iOS 16+): Settings → Privacy & Security →
   **Developer Mode** → on, then restart the phone when prompted.
5. **Verify the device is detected**:

   ```bash
   flutter devices    # should list your iPhone
   ```

6. **Build, install, and launch** on the phone:

   ```bash
   flutter run -d <deviceId>   # deviceId from `flutter devices`
   ```

   The first build is slower (CocoaPods + native compile) and starts a live
   debug session (hot reload with `r`, hot restart with `R`).
7. **Trust the developer certificate on the phone** the first time you launch a
   build signed with a personal team: Settings → General → **VPN & Device
   Management** → tap your developer profile → **Trust**. Then reopen the app.

## Testing

```bash
flutter analyze lib test integration_test
flutter test                   # unit and widget tests
flutter test integration_test  # end-to-end integration test
```

> **Note:** tests that expect `appVersion == 'dev'` assume no `APP_VERSION`
> dart-define is set. Run `flutter test` without
> `--dart-define=APP_VERSION=...` so those assertions hold.

### Simulating live goal alerts

Firing a *real* goal alert needs a Premium key, a match live right now, and a
goal scored while the Live tab is open — impractical to reproduce on demand. A
debug-only simulator feeds synthetic, score-incrementing snapshots into the real
alert pipeline (`LiveGoalMonitor` → `GoalNotificationService` → OS
notification) so you can verify it end to end on an emulator or device:

```bash
flutter run --dart-define=SIMULATE_LIVE=true
```

Open the **Live** tab (unlocked without a key while simulating) and grant the
notification permission when prompted. A scripted match then scores roughly
every five seconds, posting a real goal notification each time. The flag is a
compile-time constant, so it has no effect on normal or release builds; the
simulator lives in [`lib/dev/live_simulator.dart`](lib/dev/live_simulator.dart)
(tweak the cadence and goal sequence there).

> **Emulator tip:** prefer a **Google APIs** (non–Play Store) system image.
> Play-Store images can crash-loop Google Play Services in the background, which
> floods `logcat` and drops the `flutter run` session. Because the flag is baked
> into the built APK, you can also just relaunch the already-installed app
> instead of relying on the `flutter run` stream:
>
> ```bash
> adb shell monkey -p com.myfootball.my_football -c android.intent.category.LAUNCHER 1
> ```

## Release signing

Release APKs are signed with a persistent keystore so that updates install over
previous versions without conflicts. The key is stored as GitHub Actions secrets
and decoded at build time.

**One-time setup:**

1. Generate the keystore. Keep the file safe and out of git — if you lose it you
   can no longer ship updates that install over existing installs.

   ```bash
   keytool -genkey -v \
     -keystore android/release-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias release
   ```

2. Add two repository secrets (Settings → Secrets and variables → Actions):

   | Secret              | Value                                                      |
   |---------------------|------------------------------------------------------------|
   | `KEYSTORE_BASE64`   | `base64 -i android/release-keystore.jks` (copy the output) |
   | `KEYSTORE_PASSWORD` | The password you set above (used for both store and key)   |

The workflow writes `android/key.properties` from these secrets before building.
Locally, when `key.properties` is absent, the build falls back to the debug
signing key.
