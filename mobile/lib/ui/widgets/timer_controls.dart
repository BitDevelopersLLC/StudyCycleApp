/// The buttons under the timer.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/study_controller.dart';
import '../../domain/timer_state.dart';

/// Start, pause, resume, skip and stop, depending on what the timer is doing.
class TimerControls extends StatelessWidget {
  /// Creates the controls.
  const TimerControls({required this.controller, required this.color, super.key});

  /// The app's state.
  final StudyController controller;

  /// The main button's color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final state = controller.timer;
    final primaryStyle = FilledButton.styleFrom(
      backgroundColor: color,
      // Dark mode uses the lighter brand shades, which need dark text for contrast.
      foregroundColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      minimumSize: const Size(200, 56),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );

    final Widget primary = switch (state.status) {
      TimerStatus.idle || TimerStatus.waiting => FilledButton.icon(
        style: primaryStyle,
        onPressed: () => unawaited(controller.start()),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start focus'),
      ),
      TimerStatus.running => FilledButton.icon(
        style: primaryStyle,
        onPressed: () => unawaited(controller.pause()),
        icon: const Icon(Icons.pause_rounded),
        label: const Text('Pause'),
      ),
      TimerStatus.paused => FilledButton.icon(
        style: primaryStyle,
        onPressed: () => unawaited(controller.resume()),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Resume'),
      ),
    };

    final skipLabel = state.phase == Phase.focus ? 'Start break now' : 'End break now';
    return Column(
      children: [
        primary,
        if (state.isActive) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              if (state.status == TimerStatus.running || state.status == TimerStatus.paused)
                TextButton.icon(
                  onPressed: () => unawaited(controller.skip(expected: state.phase)),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(skipLabel),
                ),
              TextButton.icon(
                onPressed: () => unawaited(_confirmStop(context)),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('End session'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text('The focus time you have done so far is kept in your progress.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (stop ?? false) {
      await controller.stop();
    }
  }
}
