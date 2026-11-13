/// Cycle lengths, timer behavior and alert access.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/study_controller.dart';
import '../../domain/cycle_plan.dart';
import '../../domain/timer_engine.dart';
import '../../platform/phase_notifier.dart';

/// The Settings screen. Every change is saved immediately.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({required this.controller, super.key});

  /// The app's state.
  final StudyController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final plan = settings.plan;
        final theme = Theme.of(context);
        return ListView(
          children: [
            const _SectionTitle('Cycle length'),
            RadioGroup<CyclePreset>(
              groupValue: plan.preset,
              onChanged: (preset) {
                if (preset != null) {
                  unawaited(controller.updatePlan(_planFor(preset, plan)));
                }
              },
              child: Column(
                children: [
                  for (final preset in CyclePreset.values)
                    RadioListTile<CyclePreset>(
                      value: preset,
                      title: Text(preset.label),
                      subtitle: Text(
                        preset == CyclePreset.custom
                            ? 'Choose your own lengths'
                            : '${preset.focusMinutes} min focus · ${preset.breakMinutes} min break',
                      ),
                    ),
                ],
              ),
            ),
            if (plan.preset == CyclePreset.custom) ...[
              _MinutesSlider(
                label: 'Focus',
                value: plan.focusMinutes,
                min: CyclePlan.minFocusMinutes,
                max: CyclePlan.maxFocusMinutes,
                step: 5,
                onChanged: (minutes) => unawaited(
                  controller.updatePlan(
                    CyclePlan(
                      preset: CyclePreset.custom,
                      focusMinutes: minutes,
                      breakMinutes: plan.breakMinutes,
                    ),
                  ),
                ),
              ),
              _MinutesSlider(
                label: 'Break',
                value: plan.breakMinutes,
                min: CyclePlan.minBreakMinutes,
                max: CyclePlan.maxBreakMinutes,
                step: 1,
                onChanged: (minutes) => unawaited(
                  controller.updatePlan(
                    CyclePlan(
                      preset: CyclePreset.custom,
                      focusMinutes: plan.focusMinutes,
                      breakMinutes: minutes,
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'A change applies from the next focus block or break.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(),
            const _SectionTitle('Timer'),
            SwitchListTile(
              title: const Text('Start the next focus block automatically'),
              subtitle: const Text(
                'When a break ends. After ${TimerRules.maxAutoStarts} automatic starts in a '
                'row, Study Cycle waits for you, so a forgotten timer stops counting.',
              ),
              value: settings.autoStartFocus,
              onChanged: (value) => unawaited(controller.setAutoStartFocus(value: value)),
            ),
            SwitchListTile(
              title: const Text('Keep the screen on'),
              subtitle: const Text('While the timer runs and Study Cycle is open.'),
              value: settings.keepScreenOn,
              onChanged: (value) => unawaited(controller.setKeepScreenOn(value: value)),
            ),
            const Divider(),
            const _SectionTitle('Alerts'),
            ListTile(
              leading: Icon(_accessIcon(controller.alertAccess)),
              title: Text(_accessText(controller.alertAccess)),
              subtitle: controller.alertAccess == AlertAccess.blocked
                  ? const Text('Turn on notifications for Study Cycle in your phone\'s Settings.')
                  : null,
              trailing: controller.alertAccess == AlertAccess.mayBeLate
                  ? TextButton(
                      onPressed: () => unawaited(controller.openExactAlarmSettings()),
                      child: const Text('Allow'),
                    )
                  : null,
            ),
          ],
        );
      },
    ),
  );

  static CyclePlan _planFor(CyclePreset preset, CyclePlan current) {
    if (preset != CyclePreset.custom) {
      return CyclePlan.fromPreset(preset);
    }
    // Switching to Custom starts from the lengths in use, so nothing jumps.
    return CyclePlan(
      preset: CyclePreset.custom,
      focusMinutes: current.focusMinutes,
      breakMinutes: current.breakMinutes,
    );
  }

  static IconData _accessIcon(AlertAccess? access) => switch (access) {
    AlertAccess.ready => Icons.notifications_active_outlined,
    AlertAccess.mayBeLate => Icons.notification_important_outlined,
    AlertAccess.blocked || null => Icons.notifications_off_outlined,
  };

  static String _accessText(AlertAccess? access) => switch (access) {
    AlertAccess.ready => 'Alerts are on',
    AlertAccess.mayBeLate => 'Alerts may arrive late',
    AlertAccess.blocked => 'Notifications are off',
    null => 'Checking…',
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// A labeled slider for whole minutes.
class _MinutesSlider extends StatelessWidget {
  const _MinutesSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ step,
            label: '$value min',
            semanticFormatterCallback: (v) => '$label ${v.round()} ${v.round() == 1 ? 'minute' : 'minutes'}',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 64, child: Text('$value min', textAlign: TextAlign.end)),
      ],
    ),
  );
}
