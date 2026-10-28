import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/constants.dart';
import 'package:quax/space/space.dart';
import 'package:quax/space/space_card.dart';
import 'package:quax/space/space_screen.dart';

import '../community/pump_community.dart';
import '../ui/fake_images.dart';
import 'recorded_spaces.dart';

Future<List<Route<dynamic>>> _openCard(WidgetTester tester, Space space) =>
    pumpRoute(tester, Scaffold(body: SpaceCard(id: space.id)), const RouteSettings(name: '/'));

void main() {
  setUpAll(() => HttpOverrides.global = FakeImageHttpOverrides());

  group('SpaceCard', () {
    testWidgets('Should load the space and open its page from the button', (tester) async {
      final space = spaceOf(recordedSpace(hasPlayableRecording));
      final pushed = await _openCard(tester, space);

      expect(find.text(space.title), findsOneWidget, reason: 'The card shows the title X sent for the space id');
      await tester.tap(find.byType(SpaceListenButton));
      await tester.pump();

      expect(pushed.map((route) => route.settings.name), [
        routeSpace,
      ], reason: 'A space with a recording should open its page to play it');
      expect(
        (pushed.single.settings.arguments as SpaceScreenArguments).id,
        space.id,
        reason: 'The page should open the space of the card',
      );
    });

    testWidgets('Should not offer to listen when there is no recording', (tester) async {
      await _openCard(tester, spaceOf(recordedSpace(hasNoRecording)));

      final button = tester.widget<FilledButton>(
        find.descendant(of: find.byType(SpaceListenButton), matching: find.byWidgetPredicate((w) => w is FilledButton)),
      );
      expect(button.onPressed, isNull, reason: 'An ended space without recording has nothing to play');
    });
  });
}
