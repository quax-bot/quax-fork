import 'dart:convert';

import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';

/// Tokens for the two built-in tabs. Folder tabs use their folder id as the token.
/// A token is also the filter value used by the Saved screen.
const savedTabAll = 'all';
const savedTabUnfiled = 'unfiled';
const savedTabFavorites = 'favorites';

/// Resolves the ordered list of Saved tab tokens ([savedTabAll], [savedTabUnfiled]
/// and folder ids), honouring a stored custom order.
///
/// Tokens no longer valid (deleted folders) are dropped, and any token missing from
/// the stored order (newly created folders, or the built-ins) is appended in its
/// default position.
List<String> orderedSavedTabs(List<SavedTweetFolder> folders, String? storedOrder) {
  var defaults = [savedTabAll, ...folders.map((f) => f.id), savedTabUnfiled, savedTabFavorites];
  var valid = {savedTabAll, savedTabUnfiled, savedTabFavorites, ...folders.map((f) => f.id)};

  List<String> stored;
  try {
    stored = storedOrder == null || storedOrder.isEmpty
        ? <String>[]
        : (jsonDecode(storedOrder) as List).cast<String>();
  } catch (_) {
    stored = <String>[];
  }

  var order = stored.where(valid.contains).toList();
  for (var token in defaults) {
    if (!order.contains(token)) {
      order.add(token);
    }
  }

  return order;
}

/// The tabs the Saved screen shows, in their order.
List<String> visibleSavedTabs(BasePrefService prefs, List<SavedTweetFolder> folders) {
  bool shown(String option) => prefs.get<bool>(option) ?? true;
  return orderedSavedTabs(folders, prefs.get<String>(optionSavedTabOrder))
      .where((token) => switch (token) {
            savedTabAll => shown(optionSavedShowAllTab),
            // "Unfiled" only makes sense with folders, otherwise it duplicates "All"
            savedTabUnfiled => shown(optionSavedShowUnfiledTab) && folders.isNotEmpty,
            savedTabFavorites => shown(optionSavedShowFavoritesTab),
            _ => true,
          })
      .toList();
}

/// The tab the Saved screen opens on: the default tab chosen by the user while it is shown, the first tab otherwise.
String openingSavedTab(BasePrefService prefs, List<String> visibleTabs) {
  final defaultTab = prefs.get<String>(optionSavedDefaultTab);
  return visibleTabs.contains(defaultTab) ? defaultTab! : visibleTabs.firstOrNull ?? savedTabAll;
}

String savedTabLabel(L10n l10n, String token, List<SavedTweetFolder> folders) => switch (token) {
      savedTabAll => l10n.all,
      savedTabUnfiled => l10n.unfiled,
      savedTabFavorites => l10n.favorites,
      _ => folders.where((folder) => folder.id == token).firstOrNull?.name ?? token,
    };
