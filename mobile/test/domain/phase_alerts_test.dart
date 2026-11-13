import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/domain/phase_alerts.dart';
import 'package:study_cycle/domain/timer_engine.dart';
import 'package:study_cycle/domain/timer_state.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 9);
  final plan = CyclePlan.fromPreset(CyclePreset.classic);

  test('without auto start: one alert for focus end and one for break end', () {
    final rules = TimerRules(plan: plan);
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final alerts = PhaseAlertPlanner.plan(running, rules);
    expect(alerts, hasLength(2));
    expect(alerts[0].at, t0.add(const Duration(minutes: 50)));
    expect(alerts[0].title, contains('break'));
    expect(alerts[0].body, contains('10 minutes'));
    expect(alerts[1].at, t0.add(const Duration(minutes: 60)));
    expect(alerts[1].title, 'Break over');
  });

  test('during a break: only the break-end alert', () {
    final rules = TimerRules(plan: plan);
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final rest = TimerEngine.advance(running, rules, t0.add(const Duration(minutes: 55))).state;
    final alerts = PhaseAlertPlanner.plan(rest, rules);
    expect(alerts.single.at, t0.add(const Duration(minutes: 60)));
  });

  test('with auto start: follows the timer until it waits for the user', () {
    final rules = TimerRules(plan: plan, autoStartFocus: true);
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final alerts = PhaseAlertPlanner.plan(running, rules);
    // 4 focus blocks (1 + 3 automatic) each followed by a break = 8 phase ends.
    expect(alerts, hasLength(2 * (1 + TimerRules.maxAutoStarts)));
    expect(alerts[1].title, 'Break over. Focus started');
    expect(alerts.last.title, 'Break over');
    for (var i = 1; i < alerts.length; i++) {
      expect(alerts[i].at.isAfter(alerts[i - 1].at), isTrue);
    }
  });

  test('never plans more than the maximum', () {
    final rules = TimerRules(plan: plan, autoStartFocus: true);
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    expect(
      PhaseAlertPlanner.plan(running, rules).length,
      lessThanOrEqualTo(PhaseAlertPlanner.maxAlerts),
    );
  });

  test('nothing to plan unless running', () {
    final rules = TimerRules(plan: plan);
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final paused = TimerEngine.pause(running, rules, t0).state;
    expect(PhaseAlertPlanner.plan(TimerState.idle, rules), isEmpty);
    expect(PhaseAlertPlanner.plan(paused, rules), isEmpty);
  });

  test('a one-minute break uses the singular', () {
    final rules = TimerRules(
      plan: CyclePlan(preset: CyclePreset.custom, focusMinutes: 5, breakMinutes: 1),
    );
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    expect(PhaseAlertPlanner.plan(running, rules).first.body, contains('1 minute:'));
  });
}
