import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/controller/study_controller.dart';
import 'package:study_cycle/data/app_store.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/domain/timer_state.dart';
import 'package:study_cycle/platform/phase_notifier.dart';

import '../fakes.dart';

void main() {
  test('start asks for permission, schedules alerts and keeps the screen on', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();

    expect(h.notifier.requests, 1);
    expect(h.controller.timer.status, TimerStatus.running);
    expect(h.notifier.scheduled, hasLength(2));
    expect(h.screen.keptOn, isTrue);
  });

  test('the timer survives an app restart and catches up with the clock', () async {
    final first = Harness();
    await first.controller.load();
    await first.controller.start();

    // The app is closed and opened again 100 minutes later, during the break.
    final second = Harness(start: first.clock.now.add(const Duration(minutes: 100)))
      ..kv.values.addAll(first.kv.values);
    await second.controller.load();

    expect(second.controller.timer.phase, Phase.rest);
    expect(second.controller.timer.status, TimerStatus.running);
    final today = second.controller.history.dayOf(second.clock.now);
    expect(today.cycles, 1);
    expect(today.focus, const Duration(minutes: 90));
    // The remaining break alert is scheduled again.
    expect(second.notifier.scheduled, hasLength(1));
  });

  test('refresh moves to the break without rescheduling alerts', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    final scheduledAtStart = h.notifier.scheduled;

    h.clock.advance(const Duration(minutes: 90));
    await h.controller.refresh();

    expect(h.controller.timer.phase, Phase.rest);
    expect(identical(h.notifier.scheduled, scheduledAtStart), isTrue);
  });

  test('pause cancels alerts and lets the screen sleep; resume brings them back', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 10));

    await h.controller.pause();
    expect(h.notifier.scheduled, isEmpty);
    expect(h.screen.keptOn, isFalse);

    h.clock.advance(const Duration(minutes: 30));
    await h.controller.resume();
    expect(h.notifier.scheduled.first.at, h.clock.now.toUtc().add(const Duration(minutes: 80)));
    expect(h.screen.keptOn, isTrue);
  });

  test('stop keeps partial focus time and clears alerts', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 30));
    await h.controller.stop();

    expect(h.controller.timer, TimerState.idle);
    expect(h.notifier.scheduled, isEmpty);
    expect(h.controller.history.dayOf(h.clock.now).focus, const Duration(minutes: 30));
    expect(h.controller.history.dayOf(h.clock.now).cycles, 0);
  });

  test('settings are saved and reloaded', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.updatePlan(CyclePlan.fromPreset(CyclePreset.short));
    await h.controller.setAutoStartFocus(value: true);
    await h.controller.setKeepScreenOn(value: false);

    final reloaded = AppStore(h.kv).loadSettings();
    expect(reloaded.plan, CyclePlan.fromPreset(CyclePreset.short));
    expect(reloaded.autoStartFocus, isTrue);
    expect(reloaded.keepScreenOn, isFalse);
  });

  test('keep-screen-on off, or the app in the background, lets the screen sleep', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    await h.controller.setInForeground(value: false);
    expect(h.screen.keptOn, isFalse);
    await h.controller.setInForeground(value: true);
    expect(h.screen.keptOn, isTrue);
    await h.controller.setKeepScreenOn(value: false);
    expect(h.screen.keptOn, isFalse);
  });

  test('turning on auto start reschedules the alerts ahead', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    expect(h.notifier.scheduled, hasLength(2));
    await h.controller.setAutoStartFocus(value: true);
    expect(h.notifier.scheduled.length, greaterThan(2));
  });

  test('clearHistory deletes the saved history', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 95));
    await h.controller.refresh();
    expect(h.controller.history.days, isNotEmpty);

    await h.controller.clearHistory();
    expect(h.controller.history.days, isEmpty);
    expect(AppStore(h.kv).loadHistory().days, isEmpty);
  });

  test('alert access is re-checked when the app comes back', () async {
    final h = Harness();
    h.notifier.access = AlertAccess.mayBeLate;
    await h.controller.load();
    expect(h.controller.alertAccess, AlertAccess.mayBeLate);

    await h.controller.openExactAlarmSettings();
    expect(h.notifier.settingsOpened, 1);
    h.notifier.access = AlertAccess.ready;
    await h.controller.setInForeground(value: true);
    expect(h.controller.alertAccess, AlertAccess.ready);
  });

  test('a failing alert schedule never leaves the screen out of date', () async {
    final h = Harness();
    await h.controller.load();
    h.notifier.throwOnSchedule = true;
    var notified = 0;
    h.controller.addListener(() => notified++);
    await expectLater(h.controller.start(), throwsArgumentError);
    expect(h.controller.timer.status, TimerStatus.running);
    expect(notified, greaterThan(0));
    // The queue keeps working after a failure.
    h.notifier.throwOnSchedule = false;
    await h.controller.pause();
    expect(h.controller.timer.status, TimerStatus.paused);
  });

  test('coming back after a phase ended re-plans alerts from the current phase', () async {
    final h = Harness();
    h.notifier.access = AlertAccess.blocked;
    await h.controller.load();
    await h.controller.start();
    await h.controller.setInForeground(value: false);

    // While away, focus ends and the user turns notifications on in Settings.
    h.clock.advance(const Duration(minutes: 95));
    h.notifier.access = AlertAccess.ready;
    await h.controller.setInForeground(value: true);

    expect(h.controller.timer.phase, Phase.rest);
    expect(h.notifier.scheduled.single.title, 'Break over');
    expect(h.notifier.scheduled.single.at.isAfter(h.clock.now), isTrue);
  });

  test('actions run one at a time, in the order they were made', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.start();
    await Future.wait([
      h.controller.setAutoStartFocus(value: true),
      h.controller.setAutoStartFocus(value: false),
      h.controller.start(),
      h.controller.start(),
    ]);
    expect(h.controller.settings.autoStartFocus, isFalse);
    expect(h.notifier.scheduled, hasLength(2));
    expect(h.controller.timer.phaseEndsAt, h.clock.now.toUtc().add(const Duration(minutes: 90)));
  });

  test('alerts too close to now are not scheduled', () async {
    final h = Harness();
    await h.controller.load();
    await h.controller.updatePlan(
      CyclePlan(preset: CyclePreset.custom, focusMinutes: 5, breakMinutes: 1),
    );
    await h.controller.start();
    h.clock.advance(const Duration(minutes: 4, seconds: 59));
    await h.controller.pause();
    await h.controller.resume();
    // Focus ends in 1 s (too close to schedule); only the break-end alert remains.
    expect(h.notifier.scheduled.single.title, 'Break over');
  });

  test('damaged saved data starts fresh instead of crashing', () async {
    final h = Harness(
      saved: <String, Object>{'timer.v1': '{not json', 'history.v1': '[1,2,3]', 'plan.preset': 'x'},
    );
    await h.controller.load();
    expect(h.controller.timer, TimerState.idle);
    expect(h.controller.history.days, isEmpty);
    expect(h.controller.settings.plan, CyclePlan.standard());
  });

  test('the injected clock is used', () {
    final h = Harness(start: DateTime(2030));
    expect(h.controller.now, DateTime(2030));
    expect(
      StudyController(
        store: AppStore(MemoryKeyValueStore()),
        notifier: FakeNotifier(),
        screenAwake: FakeScreenAwake(),
      ).now.year,
      greaterThanOrEqualTo(2026),
    );
  });
}
