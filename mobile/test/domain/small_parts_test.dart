import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_cycle/app_info.dart';
import 'package:study_cycle/domain/break_tips.dart';
import 'package:study_cycle/domain/cycle_plan.dart';
import 'package:study_cycle/ui/brand.dart';

void main() {
  group('CyclePlan', () {
    test('the default is 90 minutes of focus and a 20-minute break', () {
      final plan = CyclePlan.standard();
      expect(plan.preset, CyclePreset.ultradian);
      expect(plan.focus, const Duration(minutes: 90));
      expect(plan.rest, const Duration(minutes: 20));
    });

    test('clamps lengths into the allowed range', () {
      final plan = CyclePlan(preset: CyclePreset.custom, focusMinutes: 0, breakMinutes: 999);
      expect(plan.focusMinutes, CyclePlan.minFocusMinutes);
      expect(plan.breakMinutes, CyclePlan.maxBreakMinutes);
    });

    test('unknown preset names fall back to the default', () {
      expect(CyclePreset.fromName('classic'), CyclePreset.classic);
      expect(CyclePreset.fromName('nope'), CyclePreset.ultradian);
      expect(CyclePreset.fromName(null), CyclePreset.ultradian);
    });
  });

  test('break tips rotate and never fail', () {
    expect(BreakTips.forCycle(1), BreakTips.all.first);
    expect(BreakTips.forCycle(2), BreakTips.all[1]);
    expect(BreakTips.forCycle(BreakTips.all.length + 1), BreakTips.all.first);
    expect(BreakTips.forCycle(0), BreakTips.all.last);
  });

  group('formatting', () {
    test('countdown', () {
      expect(formatCountdown(const Duration(minutes: 90)), '1:30:00');
      expect(formatCountdown(const Duration(minutes: 19, seconds: 59)), '19:59');
      expect(formatCountdown(const Duration(milliseconds: 400)), '0:01');
      expect(formatCountdown(Duration.zero), '0:00');
    });

    test('study time', () {
      expect(formatStudyTime(Duration.zero), '0 min');
      expect(formatStudyTime(const Duration(minutes: 45)), '45 min');
      expect(formatStudyTime(const Duration(minutes: 125)), '2 h 05 min');
    });

    test('spoken countdown', () {
      expect(spokenCountdown(const Duration(minutes: 90)), '1 hour 30 minutes left');
      expect(spokenCountdown(const Duration(minutes: 1, seconds: 1)), '1 minute 1 second left');
      expect(spokenCountdown(Duration.zero), '0 seconds left');
    });
  });

  test('AppInfo.version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version: (\S+)\+\d+$', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(AppInfo.version, version);
  });
}
