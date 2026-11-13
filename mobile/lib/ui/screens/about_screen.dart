/// How Study Cycle works, the research behind it, privacy and the open-source license.
library;

import 'package:flutter/material.dart';

import '../../app_info.dart';

/// The About screen. Links are shown as selectable text: the app has no internet access and
/// does not open web pages itself.
class AboutScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          _Section(
            title: 'How it works',
            paragraphs: [
              'Pick one task and focus on it until the timer ends. Then take a real break, '
                  'away from your screen. Repeat.',
              'Study Cycle tells you when each focus block and break ends, even when your '
                  'phone is locked.',
            ],
          ),
          _Section(
            title: 'Why 90 minutes?',
            paragraphs: [
              'Sleep researcher Nathaniel Kleitman proposed that a roughly 90-minute "basic '
                  'rest-activity cycle" continues through the day as well as during sleep.',
              'In a well-known study of expert violinists, the best players practiced in '
                  'sessions of about an hour to an hour and a half, with breaks in between, '
                  'and rarely more than four hours a day.',
              'A 2022 review of 22 studies found that short breaks reliably reduce tiredness '
                  'and can help performance.',
              'There is no proof that exactly 90 minutes is best for everyone. Use it as a '
                  'starting point, and try the 50- or 25-minute cycles, or set your own.',
            ],
            references: [
              'Kleitman, N. (1982). Basic rest-activity cycle—22 years later. Sleep, 5(4), '
                  '311–317.',
              'Ericsson, K. A., Krampe, R. T., & Tesch-Römer, C. (1993). The role of '
                  'deliberate practice in the acquisition of expert performance. '
                  'Psychological Review, 100(3), 363–406.',
              'Albulescu, P., et al. (2022). "Give me a break!" A systematic review and '
                  'meta-analysis on the efficacy of micro-breaks for increasing well-being '
                  'and performance. PLoS ONE, 17(8), e0272460.',
            ],
          ),
          _Section(
            title: 'Your privacy',
            paragraphs: [
              'Study Cycle collects no data. There are no ads, accounts, analytics or crash '
                  'reports. The Android app does not even have internet access.',
              'Your settings and progress are stored only on this phone. Uninstalling the app '
                  'deletes them.',
              'Full privacy policy: ${AppInfo.privacyUrl}',
            ],
          ),
          _Section(
            title: 'Free and open source',
            paragraphs: [
              'Study Cycle is free, with no paid upgrades. Its source code is public under '
                  'the GNU General Public License v3.0, so anyone can check what it does.',
              'Source code: ${AppInfo.sourceUrl}',
              'Questions or problems: ${AppInfo.supportEmail}',
            ],
          ),
          _Section(
            title: 'Version',
            paragraphs: ['${AppInfo.name} ${AppInfo.version} · Made by BitDevelopers LLC'],
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.paragraphs,
    this.references = const <String>[],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> references;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          for (final paragraph in paragraphs)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(paragraph, style: theme.textTheme.bodyLarge),
            ),
          if (references.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('References', style: theme.textTheme.titleSmall),
            for (final reference in references)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(reference, style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
