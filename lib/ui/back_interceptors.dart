/// Lets the pages of the home screen use the back button first.
/// A [PopScope] in a page would not do: the one that closes the app would run too.
class BackInterceptors {
  final List<bool Function()> _interceptors = [];

  void add(bool Function() interceptor) => _interceptors.add(interceptor);

  void remove(bool Function() interceptor) => _interceptors.remove(interceptor);

  /// Whether a page used the back button. The page added last goes first.
  bool intercept() => _interceptors.reversed.any((interceptor) => interceptor());
}
