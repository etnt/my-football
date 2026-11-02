import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/fixtures/fixtures_providers.dart';
import 'package:my_football/features/fixtures/fixtures_repository.dart';
import 'package:my_football/features/fixtures/fixtures_view.dart';
import 'package:my_football/features/predictions/prediction_providers.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/reminders/match_reminder.dart';
import 'package:my_football/features/reminders/reminder_notification_service.dart';
import 'package:my_football/features/reminders/reminders_providers.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records schedule/cancel calls instead of touching the OS
/// (same pattern as `reminder_sheet_test.dart`).
class _FakeNotifications extends ReminderNotificationService {
  final scheduled = <MatchReminder>[];

  @override
  Future<ReminderPermissionStatus> ensureReady() async =>
      ReminderPermissionStatus.granted;

  @override
  Future<ReminderScheduleResult> schedule(MatchReminder reminder) async {
    scheduled.add(reminder);
    return ReminderScheduleResult.scheduled;
  }

  @override
  Future<void> cancel(int fixtureId) async {}
}

PredictionResult _result() {
  return PredictionResult(
    pHome: 0.52,
    pDraw: 0.24,
    pAway: 0.24,
    displayPercents: const {
      Outcome.home: 52,
      Outcome.draw: 24,
      Outcome.away: 24,
    },
    verdict: Verdict.homeWin,
    isSlight: false,
    reasons: const [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Liverpool are 1st, Chelsea are 8th.',
      ),
    ],
    missingNotes: const [],
    completeness: Completeness.full,
    formulaVersion: 'v1',
  );
}

/// Dates are computed from `now` so the eligibility checks
/// (`MatchReminder.canRemind`) never silently go stale, unlike a fixed date.
Fixture _fixture({
  required int id,
  required String home,
  required DateTime dateUtc,
  String status = 'NS',
  bool postponed = false,
}) {
  return Fixture(
    id: id,
    dateUtc: dateUtc,
    statusShort: status,
    statusLong: '',
    elapsed: null,
    homeId: id,
    homeName: home,
    homeLogo: '',
    awayId: id + 1,
    awayName: 'Chelsea',
    awayLogo: '',
    homeGoals: null,
    awayGoals: null,
    postponed: postponed,
  );
}

Future<DateTime> _inDays(int days) async =>
    DateTime.now().toUtc().add(Duration(days: days));

Future<void> _pumpView(
  WidgetTester tester, {
  required List<Fixture> fixtures,
  _FakeNotifications? notifications,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (notifications != null)
          reminderNotificationServiceProvider.overrideWithValue(notifications),
        fixturesModeProvider.overrideWith((ref) => FixturesMode.upcoming),
        fixturesProvider.overrideWith(() => _FakeFixturesNotifier(fixtures)),
        predictionProvider(
          (
            fixtureId: fixtures.first.id,
            leagueId: 4328,
            season: 2026,
          ),
        ).overrideWith((ref) async => _result()),
        // The AI summary would otherwise arm its 8 s guard timer, which is
        // still pending at teardown (fake async). The deterministic content
        // must also never wait for the model (CON-001).
        predictionNarrationProvider(
          NarrationRequest(
            fixture: fixtures.first,
            key: (
              fixtureId: fixtures.first.id,
              leagueId: 4328,
              season: 2026,
            ),
          ),
        ).overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: FixturesView())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('long pressing an eligible upcoming match opens the '
      'prediction sheet', (tester) async {
    final kickoff = await _inDays(7);
    await _pumpView(
      tester,
      fixtures: [_fixture(id: 10, home: 'Liverpool', dateUtc: kickoff)],
    );

    await tester.longPress(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsOneWidget);
    expect(find.text('Home win'), findsOneWidget);
    expect(find.text('Liverpool 52%'), findsOneWidget);
    expect(find.text('Draw 24%'), findsOneWidget);
    expect(find.text('Chelsea 24%'), findsOneWidget);
    expect(
      find.text('Estimate based on the league table. Not betting advice.'),
      findsOneWidget,
    );
  });

  testWidgets('double-tapping an eligible upcoming match still opens the '
      'reminder sheet', (tester) async {
    final kickoff = await _inDays(7);
    final notifications = _FakeNotifications();
    await _pumpView(
      tester,
      fixtures: [_fixture(id: 10, home: 'Liverpool', dateUtc: kickoff)],
      notifications: notifications,
    );

    // Two quick taps inside the double-tap window (REQ-009: double-tap
    // behaviour stays unchanged).
    await tester.tap(find.text('Liverpool'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsNothing);
    expect(find.text('15 min before'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(notifications.scheduled, isEmpty);
  });

  testWidgets('a live match has no prediction long press', (tester) async {
    final kickoff = await _inDays(0);
    await _pumpView(
      tester,
      fixtures: [
        _fixture(id: 10, home: 'Liverpool', dateUtc: kickoff, status: '1H'),
      ],
    );

    await tester.longPress(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsNothing);
  });

  testWidgets('a postponed match has no prediction long press', (tester) async {
    final kickoff = await _inDays(7);
    await _pumpView(
      tester,
      fixtures: [
        _fixture(id: 10, home: 'Liverpool', dateUtc: kickoff, postponed: true),
      ],
    );

    await tester.longPress(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsNothing);
  });

  testWidgets('a finished match has no prediction long press', (tester) async {
    final kickoff = DateTime.now().toUtc().subtract(const Duration(days: 2));
    await _pumpView(
      tester,
      fixtures: [
        _fixture(id: 10, home: 'Liverpool', dateUtc: kickoff, status: 'FT'),
      ],
    );

    await tester.longPress(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsNothing);
  });

  testWidgets('a past not-started match has no prediction long press', (
    tester,
  ) async {
    final kickoff = DateTime.now().toUtc().subtract(const Duration(days: 2));
    await _pumpView(
      tester,
      fixtures: [_fixture(id: 10, home: 'Liverpool', dateUtc: kickoff)],
    );

    await tester.longPress(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsNothing);
  });
}

class _FakeFixturesNotifier extends FixturesNotifier {
  _FakeFixturesNotifier(this.fixtures);

  final List<Fixture> fixtures;

  @override
  Future<List<Fixture>> build() => Future.value(fixtures);
}
