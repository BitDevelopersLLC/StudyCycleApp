import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/domain/study_history.dart';
import 'package:study_cycle/domain/timer_engine.dart';
import 'package:study_cycle/domain/timer_state.dart';

void main() {
  // Local times, so day boundaries follow the test machine's time zone like the app does.
  final now = DateTime(2026, 11, 12, 15);

  CompletedPhase focus(DateTime endedAt, int minutes, {bool finished = true}) => CompletedPhase(
    phase: Phase.focus,
    duration: Duration(minutes: minutes),
    endedAt: endedAt,
    finished: finished,
  );

  test('dayKey uses the local date', () {
    expect(StudyHistory.dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });

  test('records focus time and full cycles; ignores breaks and tiny sessions', () {
    final history = StudyHistory().record([
      focus(now, 90),
      focus(now, 30, finished: false),
      CompletedPhase(
        phase: Phase.rest,
        duration: const Duration(minutes: 20),
        endedAt: now,
        finished: true,
      ),
      focus(now, 0),
      CompletedPhase(
        phase: Phase.focus,
        duration: const Duration(seconds: 30),
        endedAt: now,
        finished: false,
      ),
    ], now);
    expect(history.dayOf(now), const DayTotal(focus: Duration(minutes: 120), cycles: 1));
  });

  test('last 7 days, oldest first, with empty days as zero', () {
    final history = StudyHistory().record([
      focus(now, 50),
      focus(DateTime(2026, 11, 10, 9), 25),
    ], now);
    final week = history.lastDays(now, 7);
    expect(week, hasLength(7));
    expect(week.last.focus, const Duration(minutes: 50));
    expect(week[4].focus, const Duration(minutes: 25));
    expect(week.first, const DayTotal());
  });

  test('streak counts back from today, or from yesterday if today is empty', () {
    final days = [for (var i = 1; i <= 3; i++) focus(DateTime(2026, 11, 12 - i, 10), 90)];
    final history = StudyHistory().record(days, now);
    expect(history.streak(now), 3);
    final withToday = history.record([focus(now, 90)], now);
    expect(withToday.streak(now), 4);
    // A partial session doesn't count toward the streak.
    final partialToday = history.record([focus(now, 20, finished: false)], now);
    expect(partialToday.streak(now), 3);
    expect(StudyHistory().streak(now), 0);
  });

  test('all-time total adds every day', () {
    final history = StudyHistory().record([
      focus(now, 90),
      focus(DateTime(2026, 3, 1, 9), 50),
    ], now);
    expect(history.allTime, const DayTotal(focus: Duration(minutes: 140), cycles: 2));
  });

  test('drops days older than the retention window', () {
    final old = DateTime(now.year, now.month, now.day - StudyHistory.keepDays, 12);
    final history = StudyHistory().record([focus(old, 90), focus(now, 90)], now);
    expect(history.days.keys, [StudyHistory.dayKey(now)]);
  });

  test('round-trips through JSON and skips bad entries', () {
    final history = StudyHistory().record([focus(now, 90)], now);
    expect(StudyHistory.fromJson(history.toJson()).days, history.days);
    final damaged = StudyHistory.fromJson(<String, Object?>{
      '2026-11-12': [5400, 1],
      'not-a-date': [1, 1],
      '2026-11-11': 'oops',
      '2026-11-10': [-5, 1],
      '2026-11-09': [60],
    });
    expect(damaged.days.keys, ['2026-11-12']);
    expect(StudyHistory.fromJson(null).days, isEmpty);
  });
}
