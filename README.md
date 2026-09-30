# My Football
> Track the major football leagues

My Football is a Flutter app for following the big European football leagues.
It shows live league **standings**, **fixtures** (recent results and upcoming
matches grouped by matchweek), and per-team **schedules**. Adding a
[TheSportsDB](https://www.thesportsdb.com/) API key in Settings unlocks the
premium tier, which adds a **Live scores** tab (with phone alerts when a goal
is scored while that tab is open), **Player stats** leaderboards
(top scorers, assists & cards, with player drill-down from each row), and
richer team data.

## Screenshots

<a href="screenshots/table.jpeg"><img src="screenshots/table.jpeg" alt="League standings screenshot" width="19%"></a>
<a href="screenshots/matches.jpeg"><img src="screenshots/matches.jpeg" alt="Fixtures screenshot" width="19%"></a>
<a href="screenshots/scorers.jpeg"><img src="screenshots/scorers.jpeg" alt="Top scorers screenshot" width="19%"></a>
<a href="screenshots/assists.jpeg"><img src="screenshots/assists.jpeg" alt="Top assists screenshot" width="19%"></a>
<a href="screenshots/cards.jpeg"><img src="screenshots/cards.jpeg" alt="Cards leaderboard screenshot" width="19%"></a>

<a href="screenshots/live-score.jpeg"><img src="screenshots/live-score.jpeg" alt="Live score screenshot" width="19%"></a>
<a href="screenshots/live-scorers.jpeg"><img src="screenshots/live-scorers.jpeg" alt="Live scorers screenshot" width="19%"></a>
<a href="screenshots/config.jpeg"><img src="screenshots/config.jpeg" alt="Config screenshot" width="19%"></a>
<a href="screenshots/player_info.jpeg"><img src="screenshots/player_info.jpeg" alt="Player info screenshot" width="19%"></a>
<a href="screenshots/lineup.jpeg"><img src="screenshots/lineup.jpeg" alt="Lineup screenshot" width="19%"></a>

## Using the app

### Choose a league and season

- Tap `League` above the screen to choose a followed league.
- Tap `Season` to choose the season to display.
- Open `Settings` to change followed leagues. Choose a country, then select or clear leagues.
- Keep at least one league selected.

### Move between screens

- Tap `Table` to view league standings.
- Tap `Matches` to view results and upcoming fixtures.
- If you have a Premium key, tap `Stats` or `Live` to open those screens.
- Tap the settings icon in the top-right corner to open `Settings`.

### Table

- Tap a team row to open that team's details and schedule.
- With a Premium key, double-tap a team row to open the team's latest line-up.
- Pull down on the table to refresh the standings.

### Matches and team schedules

- Tap `Results` or `Upcoming` to switch between finished matches and future fixtures.
- Tap a matchweek heading to expand or collapse its fixtures.
- In `Results`, tap a finished match to view its goal details.
- Double-tap a finished match to view its line-up.
- In `Upcoming`, double-tap a future match to set a kick-off reminder.
- A single tap on an upcoming match does not open it.
- A reminder is available only before kick-off for a match that is not postponed.
- Choose `Off`, `15 min`, `30 min`, `60 min`, or `120 min` before kick-off.
- Tap `Save` to schedule the reminder. Choose `Off` and save to cancel it.
- For a new reminder, `15 min` is selected by default.
- Allow notifications when prompted. Without permission, reminders stay silent until you enable notifications in system settings.
- On a team's details page, tap a finished match for goal details.
- Double-tap a finished match to view its line-up.
- Double-tap an eligible upcoming match to set a reminder.
- Pull down on a match list or team schedule to refresh it.

### Stats and Live

- In `Stats`, tap `Scorers`, `Assists`, or `Cards` to choose a leaderboard.
- Tap a player row to open that player's details. Player details need a Premium key.
- In a match line-up, tap the team selector to switch between the two teams.
- Tap a player row to open details when they are available.
- In `Live`, tap a match to view its goal details. Scores refresh while this screen is open.
- The first time you open `Live`, allow notifications to receive goal alerts while this screen is open.
- Pull down on `Stats` or `Live` to refresh its data.

### Settings

- To add a Premium key, enter it in `Settings` and tap `Save`.
- Tap `Validate key` to test the key.
- Tap the eye icon to show or hide the key.
- Tap `Use free key` to remove the saved key.
- To follow a league, choose its country in `Settings`, then tap its checkbox.
- Tap a selected checkbox to unfollow that league. Keep at least one league selected.

## Download & install (Android)

Prebuilt Android APKs are published on the repository's
[**Releases**](../../releases) page, built automatically by GitHub Actions.

1. Open the latest release and download **`app-release.apk`** (the universal
   build that works on any device). Advanced users can instead pick the smaller
   ABI-specific APK matching their phone (`arm64-v8a`, `armeabi-v7a`, or
   `x86_64`).
2. On the phone, allow **Install unknown apps** for your browser or file
   manager when prompted.
3. Open the downloaded APK and confirm installation.
4. Launch the app. To enable the premium features, open **Settings** and paste a
   TheSportsDB API key (see *Free vs. premium* below).

On release builds, My Football checks GitHub for a newer release after startup,
at most once every 24 hours. If one is available, the app offers to open its
release page in your browser; development builds and offline check failures stay
silent.

> **iPhone:** direct downloads are not available. Apple does not permit
> installing apps outside the App Store, so iOS requires building from source on
> a Mac (see below) or App Store distribution.

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

### Free vs. premium

| Feature                                 | Free | Premium (API key) |
|-----------------------------------------|:----:|:-----------------:|
| League standings                        |  ✅  |        ✅         |
| Fixtures (results & upcoming)           |  ✅  |        ✅         |
| Team schedule                           |  ✅  |     ✅ (fuller)   |
| Live scores tab                         |  —   |        ✅         |
| Goal alerts while Live is open          |  —   |        ✅         |
| Player stats (scorers, assists & cards) |  —   |        ✅         |

Enter your key in **Settings**; it is stored securely on-device via
`flutter_secure_storage` and never committed to the repo.

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
│  ├─ stats/                    # scorers, assists & cards leaderboards (premium)
│  ├─ team/                     # team detail & schedule
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
  lightweight TTL response cache.
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

## License

[MPL-2.0](LICENSE).
