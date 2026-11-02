import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/repository.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/_search_field.dart';
import 'package:quax/subscriptions/_selection.dart';
import 'package:quax/subscriptions/subscriptions.dart';
import 'package:quax/ui/back_interceptors.dart';

import '../group/open_feed.dart';
import '../ui/pump_app.dart';
import 'fixtures.dart';

/// Opens the page on what [follow] and [createGroup] stored. [onAppClosed] runs when back would close the app.
Future<void> _openPage(WidgetTester tester, {Map<String, Object> prefs = const {}, VoidCallback? onAppClosed}) async {
  await pumpInApp(
      tester,
      BackInterceptorsScope(
        onBackNotUsed: (_) => onAppClosed?.call(),
        child: SubscriptionsScreen(scrollController: ScrollController()),
      ),
      prefs: {...subscriptionPrefs, ...prefs},
      aboveApp: withSubscriptionModels(),
      settle: false);
  await waitForDatabase(tester);
}

Finder _row(String name) => find.widgetWithText(ListTile, name);

Future<Set<String>> _membersOf(WidgetTester tester, String groupId) async => (await tester.runAsync(() async {
      final database = await Repository.readOnly();
      final rows = await database.query(tableSubscriptionGroupMember, where: 'group_id = ?', whereArgs: [groupId]);
      return rows.map((row) => row['profile_id'] as String).toSet();
    }))!;

void main() {
  useFreshDatabase();

  testWidgets('Should move a subscription dragged by its handle, and keep that order', (tester) async {
    await tester.runAsync(() => follow(['first', 'second', 'third'].map(account).toList()));
    await _openPage(tester, prefs: {optionSubscriptionOrderByField: 'custom'});
    final handles = find.descendant(of: find.byType(ListTile), matching: find.byIcon(Icons.drag_indicator));
    final rowHeight = tester.getCenter(handles.at(1)).dy - tester.getCenter(handles.at(0)).dy;

    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 0; step < 15; step++) {
      await gesture.moveBy(Offset(0, rowHeight / 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull, reason: 'The dragged row should draw without error');
    await gesture.up();
    await tester.pumpAndSettle();

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('second'), lessThan(top('first')), reason: '"first" should now be below "second"');
    expect(top('first'), lessThan(top('third')), reason: '"first" should stay above "third"');
    final context = tester.element(find.byType(SubscriptionsScreen));
    expect(PrefService.of(context, listen: false).get(optionSubscriptionOrderCustomKeys),
        '["user:id-second","user:id-first","user:id-third"]',
        reason: 'The new order should still be there next time');
  });

  testWidgets('Should close the search on back, without closing the app', (tester) async {
    var appClosed = false;
    await tester.runAsync(() => follow([account('alice')]));
    await _openPage(tester, onAppClosed: () => appClosed = true);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(CompactSearchField), findsNothing, reason: 'Back should close the search');
    expect(appClosed, isFalse, reason: 'Back should not close the app while the search is open');

    await tester.binding.handlePopRoute();
    expect(appClosed, isTrue, reason: 'Once the search is closed, back should close the app');
  });

  testWidgets('Should clear the selection on back, without closing the app', (tester) async {
    var appClosed = false;
    await tester.runAsync(() => follow([account('alice')]));
    await _openPage(tester, onAppClosed: () => appClosed = true);
    await tester.longPress(_row('alice'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(SelectionAppBar), findsNothing, reason: 'Back should clear the selection');
    expect(appClosed, isFalse, reason: 'Back should not close the app while subscriptions are selected');
  });

  testWidgets('Should unsubscribe from the selection, and bring it back with its groups on Undo', (tester) async {
    await tester.runAsync(() async {
      await follow([account('alice'), account('bob')]);
      await createGroup('Friends', {'id-alice'});
    });
    await _openPage(tester);
    await tester.longPress(_row('alice'));
    await tester.pump();

    await tester.tap(find.byTooltip('Unsubscribe'));
    await waitForDatabase(tester);
    expect(_row('alice'), findsNothing, reason: 'The unsubscribed account should leave the list');
    expect(_row('bob'), findsOneWidget, reason: 'The other account should stay');

    await tester.tap(find.text('Undo'));
    await waitForDatabase(tester);
    expect(find.descendant(of: _row('alice'), matching: find.text('Friends')), findsOneWidget,
        reason: 'Undo should follow the account again, in the group it was in');
  });

  testWidgets('Should put the whole selection in a group partly holding it', (tester) async {
    final groupId = await tester.runAsync(() async {
      await follow([account('alice'), account('bob')]);
      return createGroup('Friends', {'id-alice'});
    });
    await _openPage(tester);
    await tester.longPress(_row('alice'));
    await tester.tap(_row('bob'));
    await tester.pump();
    await tester.tap(find.byTooltip('Put in groups'));
    await tester.pumpAndSettle();
    CheckboxListTile choice() => tester.widget(find.widgetWithText(CheckboxListTile, 'Friends'));
    expect(choice().value, isNull, reason: 'A group holding part of the selection should be half ticked');

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Friends'));
    await waitForDatabase(tester);

    expect(await _membersOf(tester, groupId!), {'id-alice', 'id-bob'},
        reason: 'Both selected accounts should be in the group');
    expect(choice().value, isTrue, reason: 'The group should now be ticked');
  });

  testWidgets('Should show, while searching, the groups holding a matching subscription', (tester) async {
    await tester.runAsync(() async {
      await follow([account('alice'), account('bob')]);
      await createGroup('Friends', {'id-alice'});
      await createGroup('Work', {'id-bob'});
    });
    await _openPage(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CompactSearchField), 'ali');
    await tester.pumpAndSettle();

    Finder groupTile(String name) => find.descendant(of: find.byType(GroupsGrid), matching: find.text(name));
    expect(groupTile('Friends'), findsOneWidget, reason: 'The group of the matching account should show');
    expect(groupTile('Work'), findsNothing, reason: 'A group without any match should hide');
  });
}
