import 'package:material_ui/material_ui.dart';
import 'package:quax/generated/l10n.dart';

/// A button that switches to the next sort, after an arrow that reverses the order when it can be.
class SortControls extends StatelessWidget {
  final String label;
  final bool ascending;
  final bool canReverse;
  final VoidCallback onNextSort;
  final VoidCallback onReverse;

  const SortControls(
      {super.key,
      required this.label,
      required this.ascending,
      this.canReverse = true,
      required this.onNextSort,
      required this.onReverse});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canReverse)
          IconButton(
            onPressed: onReverse,
            tooltip: l10n.reverse_order,
            icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 20),
          ),
        Tooltip(
          message: l10n.sort_by,
          child: TextButton.icon(
            onPressed: onNextSort,
            icon: const Icon(Icons.swap_vert, size: 18),
            label: Text(label, semanticsLabel: l10n.sort_by_value(label)),
          ),
        ),
      ],
    );
  }
}
