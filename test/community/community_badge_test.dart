import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/client/client.dart';
import 'package:quax/community/community_screen.dart';
import 'package:quax/constants.dart';
import 'package:quax/tweet/conversation.dart';

import '../fixtures.dart';
import '../tweet/pump_tweets.dart';
import '../ui/fake_images.dart';
import '../ui/pump_app.dart';
import 'pump_community.dart';

// A search of @FlutterDev and @dart_lang, one of whose reposts was posted in a community
List<TweetChain> _searchWithACommunityPost() => Twitter.parseSearchTimeline(
        fixture('SearchTimeline', 'from-flutterdev-or-from-dart-lang-include-nativeretweets', unstable: true).body)
    .chains;

TweetWithCard _shown(TweetWithCard tweet) => tweet.retweetedStatusWithCard ?? tweet;

/// Renders [chains] in a navigator that records the screens pushed on top of them.
Future<List<Route<dynamic>>> _pumpPosts(WidgetTester tester, List<TweetChain> chains) async {
  final pushed = <Route<dynamic>>[];
  await pumpInApp(
    tester,
    withAppModels(Navigator(
      observers: [_PushObserver(pushed)],
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => settings.name == Navigator.defaultRouteName
            ? ListView(
                children: chains
                    .map((chain) =>
                        TweetConversation(id: chain.id, username: null, isPinned: chain.isPinned, tweets: chain.tweets))
                    .toList())
            : const SizedBox(),
      ),
    )),
    settle: false,
  );
  pushed.clear();
  return pushed;
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

void main() {
  setUpAll(() => HttpOverrides.global = FakeImageHttpOverrides());

  group('TweetWithCard.communityId', () {
    test('Should be the community of every post of a community timeline', () {
      final posts = Twitter.parseCommunityTimeline(recordedPosts().body).chains.expand((chain) => chain.tweets);

      expect(posts.map((tweet) => _shown(tweet).communityId), everyElement(community.id),
          reason: 'The badge of a post opens the community it was posted in');
    });

    test('Should be null for a post posted outside any community', () {
      final posts = _searchWithACommunityPost().expand((chain) => chain.tweets).map(_shown);

      expect(posts.where((tweet) => tweet.communityId == null), isNotEmpty,
          reason: 'Most posts of @FlutterDev are not in a community and should show no badge');
    });

    test('Should be kept when a post is saved', () {
      final post = _searchWithACommunityPost().expand((chain) => chain.tweets).map(_shown).firstWhere(
          (tweet) => tweet.communityId != null);

      expect(TweetWithCard.fromJson(post.toJson()).communityId, post.communityId,
          reason: 'A saved post is read back from its JSON and should still open its community');
    });
  });

  group('Community badge', () {
    testWidgets('Should open the community of a post when its badge is tapped', (tester) async {
      final chains = _searchWithACommunityPost();
      final inCommunity = chains.firstWhere((chain) => chain.tweets.any((tweet) => _shown(tweet).communityId != null));
      final communityId = inCommunity.tweets.map(_shown).firstWhere((tweet) => tweet.communityId != null).communityId;
      final pushed = await _pumpPosts(tester, [inCommunity]);

      expect(find.textContaining('Community', findRichText: true), findsOneWidget, reason: 'A post posted in a community should say so');

      await tester.tap(find.textContaining('Community', findRichText: true));
      await pumpTransition(tester);

      expect(pushed.single.settings.name, routeCommunity, reason: 'The badge opens the community screen');
      expect((pushed.single.settings.arguments as CommunityScreenArguments).id, communityId,
          reason: 'The badge should open the community the post was posted in');
    });

    testWidgets('Should not show on posts posted outside any community', (tester) async {
      final outside = _searchWithACommunityPost()
          .where((chain) => chain.tweets.every((tweet) => _shown(tweet).communityId == null))
          .take(3)
          .toList();
      await _pumpPosts(tester, outside);

      expect(find.textContaining('Community', findRichText: true), findsNothing, reason: 'Only posts of a community carry the badge');
    });
  });
}
