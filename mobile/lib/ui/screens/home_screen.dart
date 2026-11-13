/// The main screen: the timer and its controls.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/study_controller.dart';
import '../../domain/break_tips.dart';
import '../../domain/timer_state.dart';
import '../../platform/phase_notifier.dart';
import '../brand.dart';
import '../widgets/timer_controls.dart';
import '../widgets/timer_dial.dart';
import 'about_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

/// Shows the timer. Ticks once a second while a phase is running and the app is visible.
class HomeScreen extends StatefulWidget {
  /// Creates the screen.
  const HomeScreen({required this.controller, super.key});

  /// The app's state.
  final StudyController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _ticker;

  StudyController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncTicker);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    unawaited(_controller.setInForeground(value: visible));
    if (visible) {
      _syncTicker();
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Runs the one-second ticker only while a phase is counting down.
  void _syncTicker() {
    final running = _controller.timer.status == TimerStatus.running;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_controller.refresh()));
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _open(Widget screen) {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Study Cycle'),
      actions: [
        IconButton(
          tooltip: 'Progress',
          icon: const Icon(Icons.insights_outlined),
          onPressed: () => _open(ProgressScreen(controller: _controller)),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _open(SettingsScreen(controller: _controller)),
        ),
        IconButton(
          tooltip: 'About',
          icon: const Icon(Icons.info_outline),
          onPressed: () => _open(const AboutScreen()),
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _TimerBody(controller: _controller),
      ),
    ),
  );
}

class _TimerBody extends StatelessWidget {
  const _TimerBody({required this.controller});

  final StudyController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.timer;
    final now = controller.now;
    final theme = Theme.of(context);
    final color = phaseColor(state, theme.brightness);
    final today = controller.history.dayOf(now);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  if (controller.showAlertWarning) _AlertAccessBanner(controller: controller),
                  const SizedBox(height: 8),
                  TimerDial(state: state, plan: controller.settings.plan, now: now, color: color),
                  const SizedBox(height: 24),
                  _Guidance(controller: controller, color: color),
                ],
              ),
              Column(
                children: [
                  const SizedBox(height: 24),
                  TimerControls(controller: controller, color: color),
                  const SizedBox(height: 24),
                  Text(
                    'Today: ${formatStudyTime(today.focus)} focused · '
                    '${today.cycles} ${today.cycles == 1 ? 'cycle' : 'cycles'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of guidance under the dial, depending on the phase.
class _Guidance extends StatelessWidget {
  const _Guidance({required this.controller, required this.color});

  final StudyController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final state = controller.timer;
    final plan = controller.settings.plan;
    final text = switch (state.status) {
      TimerStatus.idle =>
        '${plan.focusMinutes} min focus, then a ${plan.breakMinutes} min break. '
            'Pick one task and put your phone face down.',
      TimerStatus.waiting => 'Break over. Start the next focus block when you are ready.',
      TimerStatus.paused => 'Paused. Resume when you are ready.',
      TimerStatus.running when state.phase == Phase.focus =>
        'Stay with one task. Notes and questions can wait for the break.',
      TimerStatus.running => BreakTips.forCycle(state.completedCycles),
    };
    return Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium);
  }
}

/// Explains why alerts may not arrive, with a button to fix it where the app can help.
class _AlertAccessBanner extends StatelessWidget {
  const _AlertAccessBanner({required this.controller});

  final StudyController controller;

  @override
  Widget build(BuildContext context) {
    final mayBeLate = controller.alertAccess == AlertAccess.mayBeLate;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mayBeLate
                  ? 'Alerts may arrive late while your phone is idle. Allow "Alarms & '
                        'reminders" for Study Cycle so they arrive on time.'
                  : 'Notifications are off, so you won\'t hear when a focus block or break '
                        'ends. You can turn them on in your phone\'s Settings app.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: mayBeLate
                  ? TextButton(
                      onPressed: () => unawaited(controller.openExactAlarmSettings()),
                      child: const Text('Allow'),
                    )
                  : const SizedBox(height: 8),
            ),
          ],
        ),
      ),
    );
  }
}
