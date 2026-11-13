/// Connects the timer rules to storage, notifications and the screen. The UI listens to this.
library;

import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import '../domain/cycle_plan.dart';
import '../domain/phase_alerts.dart';
import '../domain/study_history.dart';
import '../domain/timer_engine.dart';
import '../domain/timer_state.dart';
import '../platform/phase_notifier.dart';
import '../platform/screen_awake.dart';

/// Returns the current time. Injected so tests can control the clock.
typedef Clock = DateTime Function();

/// The app's single source of truth: timer state, settings and history.
///
/// Every action catches the timer up with the clock, saves the result, records finished focus
/// time, reschedules the alerts and updates the keep-screen-on flag.
class StudyController extends ChangeNotifier {
  /// Creates a controller. Call [load] before using it.
  StudyController({
    required AppStore store,
    required PhaseNotifier notifier,
    required ScreenAwake screenAwake,
    Clock? clock,
  }) : _store = store,
       _notifier = notifier,
       _screenAwake = screenAwake,
       _clock = clock ?? DateTime.now;

  final AppStore _store;
  final PhaseNotifier _notifier;
  final ScreenAwake _screenAwake;
  final Clock _clock;

  TimerState _timer = TimerState.idle;
  AppSettings _settings = AppSettings(plan: CyclePlan.standard());
  StudyHistory _history = StudyHistory();
  AlertAccess? _alertAccess;
  bool _askedForAlerts = false;
  bool _inForeground = true;

  /// The current timer state (caught up as of the last [refresh]).
  TimerState get timer => _timer;

  /// The user's settings.
  AppSettings get settings => _settings;

  /// The study history.
  StudyHistory get history => _history;

  /// Whether alerts can be shown, or null before the first check.
  AlertAccess? get alertAccess => _alertAccess;

  /// Whether to warn that alerts won't arrive (or may be late). Only after the app has asked
  /// for permission: on a new install notifications are off simply because nobody asked yet.
  bool get showAlertWarning =>
      _askedForAlerts && _alertAccess != null && _alertAccess != AlertAccess.ready;

  /// The current time from the injected clock.
  DateTime get now => _clock();

  TimerRules get _rules =>
      TimerRules(plan: _settings.plan, autoStartFocus: _settings.autoStartFocus);

  /// Loads saved data and catches the timer up (the app may have been closed for hours).
  Future<void> load() => _serial(() async {
    _timer = _store.loadTimer();
    _settings = _store.loadSettings();
    _history = _store.loadHistory();
    _askedForAlerts = _store.loadAskedForAlerts();
    _alertAccess = await _notifier.checkAccess();
    await _apply((timer) => TimerEngine.advance(timer, _rules, now), reschedule: true);
  });

  /// Catches the timer up with the clock. The UI calls this every second while it is visible.
  Future<void> refresh() =>
      _serial(() => _apply((timer) => TimerEngine.advance(timer, _rules, now)));

  /// Starts a focus block (asking for notification permission the first time).
  Future<void> start() => _serial(() async {
    _alertAccess = await _notifier.requestAccess();
    if (!_askedForAlerts) {
      _askedForAlerts = true;
      await _store.saveAskedForAlerts();
    }
    await _apply((timer) => TimerEngine.start(timer, _rules, now), reschedule: true);
  });

  /// Pauses the running phase.
  Future<void> pause() =>
      _serial(() => _apply((timer) => TimerEngine.pause(timer, _rules, now), reschedule: true));

  /// Resumes a paused phase.
  Future<void> resume() =>
      _serial(() => _apply((timer) => TimerEngine.resume(timer, _rules, now), reschedule: true));

  /// Ends the current phase early and moves to the next one. [expected] is the phase the user
  /// saw when tapping: if that phase has already ended by itself, nothing more is skipped.
  Future<void> skip({Phase? expected}) => _serial(
    () => _apply(
      (timer) => TimerEngine.skip(timer, _rules, now, expected: expected),
      reschedule: true,
    ),
  );

  /// Ends the session. Focus time already spent is kept in the history.
  Future<void> stop() =>
      _serial(() => _apply((timer) => TimerEngine.stop(timer, _rules, now), reschedule: true));

  /// Changes the cycle lengths. A phase already running keeps its length; the next one uses
  /// the new plan.
  Future<void> updatePlan(CyclePlan plan) => _updateSettings((s) => s.copyWith(plan: plan));

  /// Turns automatic focus starts on or off.
  Future<void> setAutoStartFocus({required bool value}) =>
      _updateSettings((s) => s.copyWith(autoStartFocus: value));

  /// Turns keep-screen-on on or off.
  Future<void> setKeepScreenOn({required bool value}) =>
      _updateSettings((s) => s.copyWith(keepScreenOn: value));

  /// Deletes the whole study history.
  Future<void> clearHistory() => _serial(() async {
    _history = StudyHistory();
    try {
      await _store.clearHistory();
    } finally {
      notifyListeners();
    }
  });

  /// Checks notification access again (after the user returns from system settings).
  Future<void> recheckAlertAccess() => _serial(_recheckAlertAccess);

  /// Opens the Android "Alarms & reminders" setting.
  Future<void> openExactAlarmSettings() => _notifier.openExactAlarmSettings();

  /// Tells the controller whether the app is on screen, so the screen is only kept on then.
  Future<void> setInForeground({required bool value}) => _serial(() async {
    _inForeground = value;
    if (value) {
      // Catch up first, so alerts rescheduled below are planned from the current phase.
      await _apply((timer) => TimerEngine.advance(timer, _rules, now));
      await _recheckAlertAccess();
    }
    await _updateScreen();
  });

  Future<void> _recheckAlertAccess() async {
    final access = await _notifier.checkAccess();
    if (access != _alertAccess) {
      _alertAccess = access;
      try {
        // Alerts may have been scheduled in "may be late" mode, or not at all.
        await _scheduleAlerts();
      } finally {
        notifyListeners();
      }
    }
  }

  Future<void> _updateSettings(AppSettings Function(AppSettings) change) => _serial(() async {
    _settings = change(_settings);
    await _store.saveSettings(_settings);
    // Rules changed (for example auto-start), so the planned alerts may be different.
    await _apply((timer) => TimerEngine.advance(timer, _rules, now), reschedule: true);
  });

  /// Runs [action] after every action queued before it, so actions never interleave (for
  /// example two reschedules, or a tap arriving during the one-second refresh).
  Future<void> _serial(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _queue = Future<void>.value();

  /// Applies [step] to the current timer, then saves, records history, reschedules alerts (when
  /// [reschedule]) and updates the screen. Listeners are always notified, even if a step fails.
  Future<void> _apply(TimerUpdate Function(TimerState) step, {bool reschedule = false}) async {
    final update = step(_timer);
    final changed = update.state != _timer;
    _timer = update.state;
    try {
      // The timer is saved before the history: if the app is killed in between, a few minutes
      // may go unrecorded, but the same phase can never be counted twice.
      if (changed) {
        await _store.saveTimer(_timer);
      }
      if (update.completed.isNotEmpty) {
        _history = _history.record(update.completed, now);
        await _store.saveHistory(_history);
      }
      // Alerts are planned from the state after a user action. When the clock alone moves the
      // timer on, the alerts already scheduled are still right, so they are left alone (and a
      // notification that just appeared is not cleared).
      if (reschedule) {
        await _scheduleAlerts();
      }
      if (changed || reschedule) {
        await _updateScreen();
      }
    } finally {
      // Always notify: the countdown text changes every second even when the state does not.
      notifyListeners();
    }
  }

  Future<void> _scheduleAlerts() async {
    if (_timer.status == TimerStatus.running) {
      await _notifier.schedule(PhaseAlertPlanner.plan(_timer, _rules), now: now);
    } else {
      await _notifier.cancelPending();
    }
  }

  Future<void> _updateScreen() => _screenAwake.setKeepScreenOn(
    on: _settings.keepScreenOn && _inForeground && _timer.status == TimerStatus.running,
  );
}
