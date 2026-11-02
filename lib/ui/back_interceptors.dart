import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Lets the pages of the home screen use the back button first.
/// A [PopScope] in a page would not do: the one that closes the app would run too.
class BackInterceptors {
  final List<bool Function()> _interceptors = [];

  void add(bool Function() interceptor) => _interceptors.add(interceptor);

  void remove(bool Function() interceptor) => _interceptors.remove(interceptor);

  /// Whether a page used the back button. The page added last goes first.
  bool handleBack() => _interceptors.reversed.any((interceptor) => interceptor());
}

/// Gives the back button to the pages first, and to [onBackNotUsed] when none of them used it.
class BackInterceptorsScope extends StatelessWidget {
  final void Function(BuildContext context) onBackNotUsed;
  final Widget child;

  const BackInterceptorsScope({super.key, required this.onBackNotUsed, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !context.read<BackInterceptors>().handleBack()) {
          onBackNotUsed(context);
        }
      },
      child: child,
    );
  }
}
