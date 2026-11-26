import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// Lays [child] out right to left when [text] is written right to left, in the ambient direction when it is empty.
class AutoDirection extends StatelessWidget {
  final String text;
  final Widget child;

  const AutoDirection({super.key, required this.text, required this.child});

  @override
  Widget build(BuildContext context) {
    final direction = text.isEmpty
        ? Directionality.of(context)
        : Bidi.detectRtlDirectionality(text)
            ? TextDirection.rtl
            : TextDirection.ltr;
    return Directionality(textDirection: direction, child: child);
  }
}
