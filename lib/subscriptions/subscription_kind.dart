import 'package:material_ui/material_ui.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/database/repository.dart';

/// The names are stored in the custom order: never rename them.
enum SubscriptionKind {
  user(Icons.person, tableSubscription),
  search(Icons.saved_search, tableSearchSubscription);

  const SubscriptionKind(this.icon, this.table);

  final IconData icon;
  final String table;

  static SubscriptionKind of(Subscription subscription) => switch (subscription) {
        UserSubscription() => user,
        SearchSubscription() => search,
      };
}

/// Ids of different kinds may collide.
String subscriptionKey(Subscription subscription) => '${SubscriptionKind.of(subscription).name}:${subscription.id}';

/// Kinds without any subscription are left out.
Map<SubscriptionKind, int> countByKind(Iterable<Subscription> subscriptions) => subscriptions.fold(
    {}, (counts, s) => counts..update(SubscriptionKind.of(s), (n) => n + 1, ifAbsent: () => 1));
