/// A centered column for tablets.
library;

import 'package:flutter/material.dart';

/// Centers [child] and limits it to a comfortable reading width.
///
/// On phones the screen is narrower than [maxWidth], so nothing changes. On tablets such as
/// the iPad, the content stays in a centered column instead of stretching across the screen.
class ReadableWidth extends StatelessWidget {
  /// Creates a centered column at most [maxWidth] logical pixels wide.
  const ReadableWidth({required this.child, this.maxWidth = defaultMaxWidth, super.key});

  /// The widest the content gets, in logical pixels.
  static const defaultMaxWidth = 640.0;

  /// The content, usually a scrolling list.
  final Widget child;

  /// The widest [child] may be, in logical pixels.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
