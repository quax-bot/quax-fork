import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quax/ui/auto_direction.dart';

Future<TextDirection> directionOf(WidgetTester tester, String text, {TextDirection ambient = TextDirection.ltr}) async {
  final child = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: ambient,
    child: AutoDirection(text: text, child: SizedBox(key: child)),
  ));
  return Directionality.of(child.currentContext!);
}

void main() {
  testWidgets('Should lay out an Arabic or Hebrew text right to left', (tester) async {
    expect(await directionOf(tester, 'مرحبا بالعالم'), TextDirection.rtl,
        reason: 'An Arabic tweet would otherwise start on the wrong side');
    expect(await directionOf(tester, 'שלום עולם'), TextDirection.rtl,
        reason: 'A Hebrew tweet would otherwise start on the wrong side');
  });

  testWidgets('Should lay out a Latin text left to right, even in a right to left app', (tester) async {
    expect(await directionOf(tester, 'Hello world', ambient: TextDirection.rtl), TextDirection.ltr,
        reason: 'An English tweet read in an Arabic app should still start on the left');
  });

  testWidgets('Should keep the direction of the app for an empty text', (tester) async {
    expect(await directionOf(tester, '', ambient: TextDirection.rtl), TextDirection.rtl,
        reason: 'A text without letters says nothing about its direction');
  });
}
