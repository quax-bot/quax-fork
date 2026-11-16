import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/home/_saved.dart';
import 'package:quax/saved/liked_tweet_model.dart';
import 'package:quax/saved/saved_tab_order.dart';
import 'package:quax/saved/saved_tweet_folder_model.dart';
import 'package:quax/saved/saved_tweet_model.dart';

import '../group/open_feed.dart';
import '../ui/pump_app.dart';

void main() {
  final reading = SavedTweetFolder(id: 'reading', name: 'Reading', position: 0, createdAt: DateTime(2026));

  PrefServiceCache prefs({String defaultTab = savedTabAll, bool showAll = true}) => PrefServiceCache(defaults: {
        optionSavedDefaultTab: defaultTab,
        optionSavedShowAllTab: showAll,
        optionSavedShowUnfiledTab: true,
        optionSavedShowFavoritesTab: true,
        optionSavedTabOrder: '',
      });

  group('openingSavedTab()', () {
    test('Should open on the default tab chosen by the user', () {
      final settings = prefs(defaultTab: 'reading');

      expect(openingSavedTab(settings, visibleSavedTabs(settings, [reading])), 'reading',
          reason: 'The Saved screen should open on the folder chosen as its default tab');
    });

    test('Should open on the first tab shown when the default one is hidden', () {
      final settings = prefs(showAll: false);

      expect(openingSavedTab(settings, visibleSavedTabs(settings, [reading])), 'reading',
          reason: 'With "All" hidden, the screen should open on the first tab it shows, not on a tab with no chip');
    });

    test('Should open on the first tab shown when the default folder was deleted', () {
      final settings = prefs(defaultTab: 'deleted');

      expect(openingSavedTab(settings, visibleSavedTabs(settings, [reading])), savedTabAll,
          reason: 'A deleted folder has no tab, so the screen should fall back to the first tab it shows');
    });
  });

  group('SavedScreen', () {
    useFreshDatabase();

    testWidgets('Should open on the default tab once the folders are loaded', (tester) async {
      await tester.runAsync(() => SavedTweetFolderModel().createFolder(reading.name));
      final folders = SavedTweetFolderModel();
      await tester.runAsync(folders.listFolders);
      final folderId = folders.state.single.id;

      await pumpInApp(
        tester,
        SavedScreen(scrollController: ScrollController()),
        prefs: {
          optionSavedDefaultTab: folderId,
          optionSavedShowAllTab: true,
          optionSavedShowUnfiledTab: true,
          optionSavedShowFavoritesTab: true,
          optionSavedTabOrder: '',
        },
        settle: false,
        aboveApp: (app) => MultiProvider(providers: [
          Provider(create: (_) => SavedTweetModel()),
          Provider(create: (_) => SavedTweetFolderModel()),
          Provider(create: (_) => LikedTweetModel()),
        ], child: app),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }

      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Reading'));
      expect(chip.selected, isTrue,
          reason: 'The Saved screen should open on the folder chosen as its default tab, even though the folders load '
              'after the screen is first built');
    });
  });
}
