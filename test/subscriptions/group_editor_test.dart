import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/subscriptions/group_editor.dart';

import '../group/open_feed.dart';
import '../ui/pump_app.dart';
import 'fixtures.dart';

/// Opens the editor of the group [groupId], or of a new group, once what [follow] stored is loaded.
Future<void> _openEditor(WidgetTester tester, {String? groupId}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpInApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openGroupEditor(context, id: groupId),
          child: const Text('Open the editor'),
        ),
      ),
      prefs: subscriptionPrefs,
      aboveApp: withSubscriptionModels(),
      settle: false);
  await waitForDatabase(tester);
  await tester.tap(find.text('Open the editor'));
  await waitForDatabase(tester);
}

bool? _ticked(WidgetTester tester, String name) =>
    tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, name)).value;

FilledButton _saveButton(WidgetTester tester) => tester.widget(find.widgetWithText(FilledButton, 'Save'));

void main() {
  useFreshDatabase();

  testWidgets('Should keep an unticked member in place until the group is saved', (tester) async {
    final groupId = await tester.runAsync(() async {
      await follow(['alice', 'bob', 'zoe'].map(account).toList());
      return createGroup('Friends', {'id-zoe'});
    });
    await _openEditor(tester, groupId: groupId);
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('zoe'), lessThan(top('alice')), reason: 'The members of the group should come first (#282)');

    await tester.tap(find.text('zoe'));
    await tester.pump();

    expect(_ticked(tester, 'zoe'), isFalse, reason: 'The member should be unticked');
    expect(top('zoe'), lessThan(top('alice')), reason: 'Unticking a member should not move it');
  });

  testWidgets('Should enable Save only once the group changed', (tester) async {
    final groupId = await tester.runAsync(() async {
      await follow([account('alice')]);
      return createGroup('Friends', {});
    });
    await _openEditor(tester, groupId: groupId);
    expect(_saveButton(tester).onPressed, isNull, reason: 'There is nothing to save before a change');

    await tester.tap(find.text('alice'));
    await tester.pump();

    expect(_saveButton(tester).onPressed, isNotNull, reason: 'The change can be saved');
  });

  testWidgets('Should ask for a name instead of saving a group without one', (tester) async {
    await tester.runAsync(() => follow([account('alice')]));
    await _openEditor(tester);
    await tester.tap(find.text('alice'));
    await tester.pump();

    await tester.tap(find.text('Save'));
    await waitForDatabase(tester);

    expect(find.text('Please enter a name'), findsOneWidget, reason: 'The name field should say it is needed');
    expect(find.byType(GroupEditorScreen), findsOneWidget, reason: 'The editor should stay open');
  });

  testWidgets('Should ask before dropping changes, and keep them when editing goes on', (tester) async {
    await tester.runAsync(() => follow([account('alice')]));
    await _openEditor(tester);
    await tester.tap(find.text('alice'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget, reason: 'Closing with changes should ask first');

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupEditorScreen), findsOneWidget, reason: 'The editor should stay open');
    expect(_ticked(tester, 'alice'), isTrue, reason: 'The change should be kept');
  });
}
