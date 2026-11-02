import 'package:material_ui/material_ui.dart';
import 'package:quax/database/entities.dart';

enum SubscriptionKind {
  user(Icons.person),
  search(Icons.saved_search);

  const SubscriptionKind(this.icon);

  final IconData icon;

  static SubscriptionKind of(Subscription subscription) => subscription is SearchSubscription ? search : user;
}

/// Ids of different kinds may collide.
String subscriptionKey(Subscription subscription) => '${SubscriptionKind.of(subscription).name}:${subscription.id}';

Map<SubscriptionKind, int> countByKind(Iterable<Subscription> subscriptions) => {
      for (final kind in SubscriptionKind.values)
        if (subscriptions.any((s) => SubscriptionKind.of(s) == kind))
          kind: subscriptions.where((s) => SubscriptionKind.of(s) == kind).length,
    };
