import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/domain/timer_engine.dart';
import 'package:study_cycle/domain/timer_state.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 9);
  final plan = CyclePlan(preset: CyclePreset.custom, focusMinutes: 90, breakMinutes: 20);
  final rules = TimerRules(plan: plan);
  final autoRules = TimerRules(plan: plan, autoStartFocus: true);
  DateTime at(int minutes, [int seconds = 0]) =>
      t0.add(Duration(minutes: minutes, seconds: seconds));

  TimerState started() => TimerEngine.start(TimerState.idle, rules, t0).state;

  group('start', () {
    test('from idle runs a full focus block', () {
      final state = started();
      expect(state.status, TimerStatus.running);
      expect(state.phase, Phase.focus);
      expect(state.completedCycles, 0);
      expect(state.phaseLength, const Duration(minutes: 90));
      expect(state.phaseEndsAt, at(90));
    });

    test('does nothing to a running timer', () {
      final state = started();
      expect(TimerEngine.start(state, rules, at(10)).state, state);
    });

    test('from waiting keeps the cycle count', () {
      final waiting = TimerEngine.advance(started(), rules, at(110)).state;
      expect(waiting.status, TimerStatus.waiting);
      final next = TimerEngine.start(waiting, rules, at(120)).state;
      expect(next.status, TimerStatus.running);
      expect(next.phase, Phase.focus);
      expect(next.completedCycles, 1);
      expect(next.phaseEndsAt, at(210));
    });
  });

  group('advance', () {
    test('before the end changes nothing', () {
      final update = TimerEngine.advance(started(), rules, at(89, 59));
      expect(update.state, started());
      expect(update.completed, isEmpty);
    });

    test('focus ends exactly on time and a break starts at that moment', () {
      final update = TimerEngine.advance(started(), rules, at(90));
      expect(update.state.phase, Phase.rest);
      expect(update.state.status, TimerStatus.running);
      expect(update.state.completedCycles, 1);
      expect(update.state.phaseEndsAt, at(110));
      expect(update.completed, hasLength(1));
      expect(update.completed.single.phase, Phase.focus);
      expect(update.completed.single.duration, const Duration(minutes: 90));
      expect(update.completed.single.finished, isTrue);
      expect(update.completed.single.endedAt, at(90));
    });

    test('after a long absence, catches up and waits after the break', () {
      final update = TimerEngine.advance(started(), rules, at(600));
      expect(update.state.status, TimerStatus.waiting);
      expect(update.state.completedCycles, 1);
      expect(update.completed.map((p) => p.phase), [Phase.focus, Phase.rest]);
      expect(update.completed.last.endedAt, at(110));
    });

    test('auto start continues, but stops after the auto-start limit', () {
      final start = TimerEngine.start(TimerState.idle, autoRules, t0).state;
      final update = TimerEngine.advance(start, autoRules, at(24 * 60));
      // 1 started by the user + 3 automatic = 4 focus blocks, then it waits.
      expect(update.state.status, TimerStatus.waiting);
      expect(update.state.completedCycles, 1 + TimerRules.maxAutoStarts);
      final focusBlocks = update.completed.where((p) => p.phase == Phase.focus);
      expect(focusBlocks, hasLength(1 + TimerRules.maxAutoStarts));
    });

    test('auto start runs the next focus block right after the break', () {
      final start = TimerEngine.start(TimerState.idle, autoRules, t0).state;
      final update = TimerEngine.advance(start, autoRules, at(115));
      expect(update.state.status, TimerStatus.running);
      expect(update.state.phase, Phase.focus);
      expect(update.state.phaseEndsAt, at(200));
      expect(update.state.autoStarts, 1);
    });

    test('a user action resets the auto-start count', () {
      final start = TimerEngine.start(TimerState.idle, autoRules, t0).state;
      final auto = TimerEngine.advance(start, autoRules, at(115)).state;
      final paused = TimerEngine.pause(auto, autoRules, at(120)).state;
      final resumed = TimerEngine.resume(paused, autoRules, at(121)).state;
      expect(resumed.autoStarts, 0);
    });
  });

  group('pause and resume', () {
    test('pause keeps the time left and resume continues from it', () {
      final paused = TimerEngine.pause(started(), rules, at(30)).state;
      expect(paused.status, TimerStatus.paused);
      expect(paused.remaining, const Duration(minutes: 60));
      expect(paused.remainingAt(at(500)), const Duration(minutes: 60));

      final resumed = TimerEngine.resume(paused, rules, at(100)).state;
      expect(resumed.status, TimerStatus.running);
      expect(resumed.phaseEndsAt, at(160));
      expect(resumed.phaseLength, const Duration(minutes: 90));
    });

    test('a paused timer never advances', () {
      final paused = TimerEngine.pause(started(), rules, at(30)).state;
      final update = TimerEngine.advance(paused, rules, at(10000));
      expect(update.state, paused);
      expect(update.completed, isEmpty);
    });

    test('pausing after the end first catches up', () {
      final update = TimerEngine.pause(started(), rules, at(95));
      expect(update.completed.single.phase, Phase.focus);
      expect(update.state.status, TimerStatus.paused);
      expect(update.state.phase, Phase.rest);
      expect(update.state.remaining, const Duration(minutes: 15));
    });

    test('resume on a non-paused timer just catches up', () {
      final update = TimerEngine.resume(started(), rules, at(10));
      expect(update.state, started());
    });
  });

  group('skip', () {
    test('skipping focus records the partial time and starts the break now', () {
      final update = TimerEngine.skip(started(), rules, at(40));
      expect(update.completed.single.duration, const Duration(minutes: 40));
      expect(update.completed.single.finished, isFalse);
      expect(update.state.phase, Phase.rest);
      expect(update.state.completedCycles, 1);
      expect(update.state.phaseEndsAt, at(60));
    });

    test('skipping a break starts focus at once', () {
      final rest = TimerEngine.advance(started(), rules, at(95)).state;
      final update = TimerEngine.skip(rest, rules, at(100));
      expect(update.state.status, TimerStatus.running);
      expect(update.state.phase, Phase.focus);
      expect(update.state.phaseEndsAt, at(190));
    });

    test('skipping while paused uses the time spent before the pause', () {
      final paused = TimerEngine.pause(started(), rules, at(20)).state;
      final update = TimerEngine.skip(paused, rules, at(80));
      expect(update.completed.single.duration, const Duration(minutes: 20));
      expect(update.state.phaseEndsAt, at(100));
    });

    test('skip from waiting starts focus; skip from idle does nothing', () {
      final waiting = TimerEngine.advance(started(), rules, at(200)).state;
      expect(TimerEngine.skip(waiting, rules, at(201)).state.phase, Phase.focus);
      expect(TimerEngine.skip(TimerState.idle, rules, at(1)).state, TimerState.idle);
    });
  });

  group('stop', () {
    test('keeps the focus time spent so far', () {
      final update = TimerEngine.stop(started(), rules, at(45));
      expect(update.state, TimerState.idle);
      expect(update.completed.single.phase, Phase.focus);
      expect(update.completed.single.duration, const Duration(minutes: 45));
      expect(update.completed.single.finished, isFalse);
    });

    test('right after starting records nothing', () {
      final update = TimerEngine.stop(started(), rules, t0);
      expect(update.completed, isEmpty);
    });

    test('late stop catches up first, then records the partial break', () {
      final update = TimerEngine.stop(started(), rules, at(100));
      expect(update.completed.map((p) => p.phase), [Phase.focus, Phase.rest]);
      expect(update.completed.first.finished, isTrue);
      expect(update.completed.last.duration, const Duration(minutes: 10));
    });

    test('from waiting or idle returns to idle', () {
      final waiting = TimerEngine.advance(started(), rules, at(200)).state;
      expect(TimerEngine.stop(waiting, rules, at(201)).state, TimerState.idle);
      expect(TimerEngine.stop(TimerState.idle, rules, t0).state, TimerState.idle);
    });
  });

  test('a plan change applies from the next phase only', () {
    final running = started();
    final shorter = TimerRules(plan: CyclePlan.fromPreset(CyclePreset.short));
    final update = TimerEngine.advance(running, shorter, at(90));
    expect(update.completed.single.duration, const Duration(minutes: 90));
    expect(update.state.phaseLength, const Duration(minutes: 5));
  });
}
