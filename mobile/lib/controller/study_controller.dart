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
  Future<void> load() async {
    _timer = _store.loadTimer();
    _settings = _store.loadSettings();
    _history = _store.loadHistory();
    _askedForAlerts = _store.loadAskedForAlerts();
    _alertAccess = await _notifier.checkAccess();
    await _apply(TimerEngine.advance(_timer, _rules, now), reschedule: true);
  }

  /// Catches the timer up with the clock. The UI calls this every second while it is visible.
  Future<void> refresh() => _apply(TimerEngine.advance(_timer, _rules, now));

  /// Starts a focus block (asking for notification permission the first time).
  Future<void> start() async {
    _alertAccess = await _notifier.requestAccess();
    if (!_askedForAlerts) {
      _askedForAlerts = true;
      await _store.saveAskedForAlerts();
    }
    await _apply(TimerEngine.start(_timer, _rules, now), reschedule: true);
  }

  /// Pauses the running phase.
  Future<void> pause() => _apply(TimerEngine.pause(_timer, _rules, now), reschedule: true);

  /// Resumes a paused phase.
  Future<void> resume() => _apply(TimerEngine.resume(_timer, _rules, now), reschedule: true);

  /// Ends the current phase early and moves to the next one.
  Future<void> skip() => _apply(TimerEngine.skip(_timer, _rules, now), reschedule: true);

  /// Ends the session. Focus time already spent is kept in the history.
  Future<void> stop() => _apply(TimerEngine.stop(_timer, _rules, now), reschedule: true);

  /// Changes the cycle lengths. A phase already running keeps its length; the next one uses
  /// the new plan.
  Future<void> updatePlan(CyclePlan plan) => _updateSettings(_settings.copyWith(plan: plan));

  /// Turns automatic focus starts on or off.
  Future<void> setAutoStartFocus({required bool value}) =>
      _updateSettings(_settings.copyWith(autoStartFocus: value));

  /// Turns keep-screen-on on or off.
  Future<void> setKeepScreenOn({required bool value}) =>
      _updateSettings(_settings.copyWith(keepScreenOn: value));

  /// Deletes the whole study history.
  Future<void> clearHistory() async {
    _history = StudyHistory();
    await _store.clearHistory();
    notifyListeners();
  }

  /// Checks notification access again (after the user returns from system settings).
  Future<void> recheckAlertAccess() async {
    final access = await _notifier.checkAccess();
    if (access != _alertAccess) {
      _alertAccess = access;
      // Alerts were scheduled in "may be late" mode; schedule them again as exact.
      await _scheduleAlerts();
      notifyListeners();
    }
  }

  /// Opens the Android "Alarms & reminders" setting.
  Future<void> openExactAlarmSettings() => _notifier.openExactAlarmSettings();

  /// Tells the controller whether the app is on screen, so the screen is only kept on then.
  Future<void> setInForeground({required bool value}) async {
    _inForeground = value;
    if (value) {
      await recheckAlertAccess();
      await refresh();
    }
    await _updateScreen();
  }

  Future<void> _updateSettings(AppSettings settings) async {
    _settings = settings;
    await _store.saveSettings(settings);
    // Rules changed (for example auto-start), so the planned alerts may be different.
    await _apply(TimerEngine.advance(_timer, _rules, now), reschedule: true);
  }

  Future<void> _apply(TimerUpdate update, {bool reschedule = false}) async {
    final changed = update.state != _timer;
    _timer = update.state;
    if (update.completed.isNotEmpty) {
      _history = _history.record(update.completed, now);
      await _store.saveHistory(_history);
    }
    if (changed) {
      await _store.saveTimer(_timer);
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
    // Always notify: the countdown text changes every second even when the state does not.
    notifyListeners();
  }

  Future<void> _scheduleAlerts() async {
    if (_timer.status == TimerStatus.running) {
      await _notifier.schedule(PhaseAlertPlanner.plan(_timer, _rules));
    } else {
      await _notifier.cancelPending();
    }
  }

  Future<void> _updateScreen() => _screenAwake.setKeepScreenOn(
    on: _settings.keepScreenOn && _inForeground && _timer.status == TimerStatus.running,
  );
}
