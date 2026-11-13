import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/app.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/domain/timer_state.dart';
import 'package:study_cycle/platform/phase_notifier.dart';

import '../fakes.dart';

void main() {
  /// A typical phone screen (412 x 915 logical pixels).
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<Harness> pumpApp(WidgetTester tester, {Harness? harness}) async {
    usePhoneScreen(tester);
    final h = harness ?? Harness();
    await h.controller.load();
    await tester.pumpWidget(StudyCycleApp(controller: h.controller));
    return h;
  }

  testWidgets('home shows the plan and starts a focus block', (tester) async {
    final h = await pumpApp(tester);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('1:30:00'), findsOneWidget);
    expect(find.textContaining('90 min focus'), findsOneWidget);

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(h.controller.timer.status, TimerStatus.running);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Cycle 1'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Focus paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('ending a session asks first', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('Start focus'));
    await tester.pump();

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(h.controller.timer.status, TimerStatus.running);

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'End session').last);
    await tester.pumpAndSettle();
    expect(h.controller.timer.status, TimerStatus.idle);
  });

  testWidgets('during a break, a break tip and "End break now" show', (tester) async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 91));
    await h.controller.refresh();
    usePhoneScreen(tester);
    await tester.pumpWidget(StudyCycleApp(controller: h.controller));

    expect(find.text('Break'), findsOneWidget);
    expect(find.text('End break now'), findsOneWidget);
    expect(find.textContaining('stretch'), findsOneWidget);
  });

  testWidgets('a banner explains late alerts and opens the setting', (tester) async {
    final h = Harness();
    h.notifier.access = AlertAccess.mayBeLate;
    await pumpApp(tester, harness: h);
    // No warning before the app has asked for permission.
    expect(find.textContaining('Alarms & reminders'), findsNothing);
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(find.textContaining('Alarms & reminders'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    expect(h.notifier.settingsOpened, 1);
  });

  testWidgets('settings change the preset and show custom sliders', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(h.controller.settings.plan, CyclePlan.fromPreset(CyclePreset.classic));
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(h.controller.settings.plan.preset, CyclePreset.custom);
    expect(h.controller.settings.plan.focusMinutes, 50);
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.tap(find.text('Start the next focus block automatically'));
    await tester.pumpAndSettle();
    expect(h.controller.settings.autoStartFocus, isTrue);
  });

  testWidgets('progress shows totals and deletes history after confirming', (tester) async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 95));
    await h.controller.refresh();
    usePhoneScreen(tester);
    await tester.pumpWidget(StudyCycleApp(controller: h.controller));

    await tester.tap(find.byTooltip('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('1 h 30 min'), findsWidgets);
    expect(find.text('1 day'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Delete my progress'), 200);
    await tester.tap(find.text('Delete my progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(h.controller.history.days, isEmpty);
  });

  testWidgets('about explains the research and the privacy promise', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();
    expect(find.text('Why 90 minutes?'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('collects no data'), 200);
    expect(find.textContaining('collects no data'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('GNU General Public License'), 200);
    expect(find.textContaining('GNU General Public License'), findsOneWidget);
  });

  testWidgets('dark mode renders', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);
    expect(find.text('Start focus'), findsOneWidget);
  });
}
