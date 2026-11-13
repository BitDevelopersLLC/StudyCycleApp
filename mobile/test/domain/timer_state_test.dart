import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/domain/timer_engine.dart';
import 'package:study_cycle/domain/timer_state.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 9);
  final rules = TimerRules(plan: CyclePlan.standard());

  test('round-trips through JSON in every status', () {
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final paused = TimerEngine.pause(running, rules, t0.add(const Duration(minutes: 3))).state;
    final waiting = TimerEngine.advance(running, rules, t0.add(const Duration(hours: 5))).state;
    for (final state in [TimerState.idle, running, paused, waiting]) {
      expect(TimerState.fromJson(state.toJson()), state, reason: state.status.name);
    }
  });

  test('missing or damaged data falls back to idle', () {
    expect(TimerState.fromJson(null), TimerState.idle);
    expect(TimerState.fromJson(<String, Object?>{'status': 'flying'}), TimerState.idle);
    expect(
      TimerState.fromJson(<String, Object?>{
        'status': 'running',
        'phase': 'focus',
        'cycles': 0,
        'lengthMs': 1000,
        // A running timer without an end time is invalid.
      }),
      TimerState.idle,
    );
    expect(
      TimerState.fromJson(<String, Object?>{
        'status': 'paused',
        'phase': 'focus',
        'cycles': -1,
        'lengthMs': 1000,
        'remainingMs': 10,
      }),
      TimerState.idle,
    );
  });

  test('remaining and progress at a moment', () {
    final running = TimerEngine.start(TimerState.idle, rules, t0).state;
    final halfway = t0.add(const Duration(minutes: 45));
    expect(running.remainingAt(halfway), const Duration(minutes: 45));
    expect(running.progressAt(halfway), closeTo(0.5, 1e-9));
    expect(running.remainingAt(t0.add(const Duration(days: 1))), Duration.zero);
    expect(running.progressAt(t0.subtract(const Duration(minutes: 5))), 0);
    expect(TimerState.idle.progressAt(t0), 0);
  });
}
