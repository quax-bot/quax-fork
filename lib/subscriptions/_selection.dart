import 'package:flutter_triple/flutter_triple.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/group_editor.dart';
import 'package:quax/subscriptions/users_model.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Subscription> selected;
  final VoidCallback onClear;

  const SelectionAppBar({super.key, required this.selected, required this.onClear});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    final accounts = selected.whereType<UserSubscription>().toList();
    final allHiddenFromFeed = accounts.isNotEmpty && accounts.every((s) => !s.inFeed);
    return AppBar(
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      leading: IconButton(icon: const Icon(Icons.close), tooltip: l10n.close, onPressed: onClear),
      title: Text(l10n.n_selected(selected.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: l10n.put_in_groups,
          onPressed: () => showGroupsSheet(context, selected, onDone: onClear),
        ),
        if (accounts.isNotEmpty)
          IconButton(
            icon: Icon(allHiddenFromFeed ? Icons.visibility : Icons.visibility_off_outlined),
            tooltip: allHiddenFromFeed ? l10n.show_in_main_feed : l10n.hide_from_main_feed,
            onPressed: () => context.read<SubscriptionsModel>().setShownInMainFeed(accounts, shown: allHiddenFromFeed),
          ),
        IconButton(
          icon: const Icon(Icons.person_remove_outlined),
          tooltip: l10n.unsubscribe,
          onPressed: () => _unsubscribe(context),
        ),
      ],
    );
  }

  Future<void> _unsubscribe(BuildContext context) async {
    final l10n = L10n.of(context);
    final model = context.read<SubscriptionsModel>();
    final messenger = ScaffoldMessenger.of(context);
    // Cleared first, so that a second tap can't unsubscribe again
    onClear();
    final removed = await model.unsubscribe(selected);
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.n_subscriptions_removed(removed.subscriptions.length)),
      action: SnackBarAction(label: l10n.undo, onPressed: () => model.resubscribe(removed)),
    ));
  }
}

enum _GroupsSheetChoice { done, newGroup }

Future<void> showGroupsSheet(BuildContext context, List<Subscription> selected, {required VoidCallback onDone}) async {
  final choice = await showModalBottomSheet<_GroupsSheetChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupsSheet(selected: selected),
  );
  if (context.mounted) {
    await context.read<GroupsModel>().reloadGroups();
  }
  switch (choice) {
    case _GroupsSheetChoice.done:
      onDone();
    case _GroupsSheetChoice.newGroup when context.mounted:
      if (await openGroupEditor(context, initialMembers: selected.map((s) => s.id).toSet())) {
        onDone();
      }
    default:
  }
}

class _GroupsSheet extends StatelessWidget {
  final List<Subscription> selected;

  const _GroupsSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final groups = context.read<GroupsModel>();
    return ScopedBuilder<GroupMembershipsModel, Map<String, Set<String>>>(
      store: context.read<GroupMembershipsModel>(),
      onState: (_, members) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: Text(l10n.put_in_groups, style: Theme.of(context).textTheme.titleLarge),
                subtitle: Text(membersSummary(context, selected)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: groups.state
                      .map((group) => _GroupChoice(group: group, members: members[group.id] ?? const {}, selected: selected))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, _GroupsSheetChoice.newGroup),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.new_group),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context, _GroupsSheetChoice.done), child: Text(l10n.done)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupChoice extends StatelessWidget {
  final SubscriptionGroup group;
  final Set<String> members;
  final List<Subscription> selected;

  const _GroupChoice({required this.group, required this.members, required this.selected});

  @override
  Widget build(BuildContext context) {
    final selectedIds = selected.map((s) => s.id).toList();
    final selectedInGroup = selectedIds.where(members.contains).length;
    final wholeSelectionInGroup = selectedInGroup == selectedIds.length;
    final tone = groupTone(context, group.color);
    return CheckboxListTile(
      tristate: true,
      value: wholeSelectionInGroup ? true : (selectedInGroup == 0 ? false : null),
      secondary: CircleAvatar(
        backgroundColor: tone.background,
        child: Icon(group.iconData, color: tone.foreground, size: 22),
      ),
      title: Text(group.name),
      subtitle: Text(_subtitle(context, selectedInGroup, selectedIds.length)),
      onChanged: (_) => _toggle(context, selectedIds),
    );
  }

  /// Puts the whole selection in the group, or takes it out when it is all there.
  Future<void> _toggle(BuildContext context, List<String> selectedIds) async {
    final groups = context.read<GroupsModel>();
    final memberships = context.read<GroupMembershipsModel>();
    // Read again rather than from the build: a quick second tap comes before the sheet shows the first one
    final members = memberships.state[group.id] ?? const {};
    await (selectedIds.every(members.contains)
        ? groups.removeMembers(group.id, selectedIds)
        : groups.addMembers(group.id, selectedIds.where((id) => !members.contains(id))));
    await memberships.reload();
  }

  String _subtitle(BuildContext context, int selectedInGroup, int selectedCount) {
    final l10n = L10n.of(context);
    if (selectedInGroup == selectedCount) {
      return l10n.whole_selection_in_group;
    }
    if (selectedInGroup > 0) {
      return l10n.part_of_selection_in_group(selectedInGroup, selectedCount);
    }
    // None of the selection is in the group yet: it shows what the group holds
    final groupMembers = context.read<SubscriptionsModel>().state.where((s) => members.contains(s.id));
    return membersSummary(context, groupMembers);
  }
}
