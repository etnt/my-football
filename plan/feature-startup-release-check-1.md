---
goal: Check for newer My Football releases at startup
version: 1.0
date_created: 2026-09-29
last_updated: 2026-09-29
owner: etnt
status: 'Completed'
tags: [feature, releases, flutter]
---

# Introduction

![Status: Completed](https://img.shields.io/badge/status-Completed-brightgreen)

Implement issue #10 by checking the `etnt/my-football` GitHub Releases endpoint after the first app frame, throttling successful checks across restarts, and prompting users only when a newer release exists.

## 1. Requirements & Constraints

- **REQ-001**: Check for a newer `etnt/my-football` release once after app startup.
- **REQ-002**: When a newer release exists, show its version and available release notes with Later and Update now actions; only Update now opens the release page.
- **REQ-003**: Persist successful-check time and throttle checks to at most once per 24 hours across app restarts.
- **REQ-004**: Keep development builds (`APP_VERSION=dev`) and update-check failures silent.
- **SEC-001**: Do not add permissions; configure Android package visibility only for opening HTTPS release URLs.
- **CON-001**: Follow existing Flutter/Riverpod/SharedPreferences conventions and the `auto_upgrade` integration used in `skyoverhead` commit `6973c24a`.
- **PAT-001**: Defer UI prompting until after the first frame and guard widget context after asynchronous work.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Wire the package, persistent check, startup prompt, and release-page action.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add `auto_upgrade` and `url_launcher` dependencies; define a Riverpod `ReleaseChecker` for owner `etnt`, repo `my-football`, and `appVersion`; override it in `lib/main.dart` with `SharedPrefsUpdateCheckStore`. | ✅ | 2026-09-29 |
| TASK-002 | Add an after-first-frame check in `lib/features/home/home_shell.dart`; show a prompt only for `UpdateAvailable`; open the release URL only after Update now. | ✅ | 2026-09-29 |
| TASK-003 | Add focused prompt and app-startup widget tests; add the Android HTTPS VIEW query and README behavior; run tests, analysis, and Android debug build. | ✅ | 2026-09-29 |

## 3. Alternatives

- **ALT-001**: Check on every launch without persistence; not selected because it causes repeat GitHub requests and the reference app uses a persistent 24-hour throttle.
- **ALT-002**: Download or install APKs in-app; not selected because `auto_upgrade` is headless and the reference integration opens the GitHub release page after explicit user action.

## 4. Dependencies

- **DEP-001**: `auto_upgrade` Git package for GitHub Releases lookup, version comparison, and SharedPreferences-backed throttling.
- **DEP-002**: `url_launcher` for opening the release page in the external browser.
- **DEP-003**: Existing `shared_preferences` and Riverpod setup for persistent state and dependency injection.

## 5. Files

- **FILE-001**: `pubspec.yaml` and `pubspec.lock` — add package dependencies and resolve the lockfile.
- **FILE-002**: `lib/providers/update_provider.dart` — provide the release checker.
- **FILE-003**: `lib/main.dart` — override the checker with persistent throttling.
- **FILE-004**: `lib/features/home/home_shell.dart` — launch the check after startup and handle the user prompt/action.
- **FILE-005**: `lib/features/home/update_prompt.dart` — render the update dialog and silence non-update results.
- **FILE-006**: `android/app/src/main/AndroidManifest.xml` — declare the HTTPS VIEW query.
- **FILE-007**: `test/features/home/update_prompt_test.dart` — verify prompt result paths and actions.
- **FILE-008**: `README.md` — document startup update checks and explicit release-page opening.
- **FILE-009**: `test/widget_test.dart` — verify the app invokes its release checker at startup.

## 6. Testing

- **TEST-001**: Widget-test UpdateAvailable versions/notes, Later dismissal, and Update now callback.
- **TEST-002**: Widget-test UpToDate, CheckSkipped, and CheckError remain silent.
- **TEST-003**: Run the full Flutter test suite and static analysis, exercise the real `MyFootballApp` startup surface with a fake checker, and build the Android debug APK.

## 7. Risks & Assumptions

- **RISK-001**: GitHub API/network failures must not interrupt startup; `ReleaseChecker.check()` reports these as `CheckError`, which remains silent and is not throttled.
- **ASSUMPTION-001**: Release builds inject their tag through the existing `APP_VERSION` build define; development builds retain the existing `dev` default.

## 8. Related Specifications / Further Reading

- GitHub issue [#10](https://github.com/etnt/my-football/issues/10).
- Reference integration: `skyoverhead` commit `6973c24a`.
- [`auto_upgrade` package documentation](https://github.com/etnt/auto_upgrade).
