/// Study totals: today, the last 7 days, the streak and all time.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/study_controller.dart';
import '../../domain/study_history.dart';
import '../brand.dart';

/// The Progress screen. Everything shown here is stored only on this device.
class ProgressScreen extends StatelessWidget {
  /// Creates the screen.
  const ProgressScreen({required this.controller, super.key});

  /// The app's state.
  final StudyController controller;

  static const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Progress')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final now = controller.now;
        final history = controller.history;
        final today = history.dayOf(now);
        final week = history.lastDays(now, 7);
        final weekTotal = week.fold(const DayTotal(), (sum, day) => sum + day);
        final streak = history.streak(now);
        final allTime = history.allTime;
        final theme = Theme.of(context);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Today',
                    value: formatStudyTime(today.focus),
                    detail: '${today.cycles} ${today.cycles == 1 ? 'cycle' : 'cycles'}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Streak',
                    value: '$streak ${streak == 1 ? 'day' : 'days'}',
                    detail: 'with a full cycle',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last 7 days', style: theme.textTheme.titleMedium),
                    Text(
                      '${formatStudyTime(weekTotal.focus)} · ${weekTotal.cycles} cycles',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _WeekChart(
                      days: week,
                      labels: [
                        for (var i = 6; i >= 0; i--)
                          _weekdays[DateTime(now.year, now.month, now.day - i).weekday - 1],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _StatCard(
              title: 'All time',
              value: formatStudyTime(allTime.focus),
              detail: '${allTime.cycles} ${allTime.cycles == 1 ? 'cycle' : 'cycles'}',
            ),
            const SizedBox(height: 24),
            Text(
              'Your progress is stored only on this phone. Study Cycle never sends it anywhere.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: history.days.isEmpty ? null : () => unawaited(_confirmClear(context)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete my progress'),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _confirmClear(BuildContext context) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all progress?'),
        content: const Text('This removes every day of study history. It can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (clear ?? false) {
      await controller.clearHistory();
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.detail});

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Seven bars of focus time, tallest = busiest day.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.labels});

  final List<DayTotal> days;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? BrandColors.focus
        : BrandColors.focusDark;
    final most = days.fold(Duration.zero, (max, day) => day.focus > max ? day.focus : max);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Semantics(
                label: '${labels[i]}: ${formatStudyTime(days[i].focus)}',
                excludeSemantics: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: most == Duration.zero
                          ? 2
                          : 2 + 98 * days[i].focus.inSeconds / most.inSeconds,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i], style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
