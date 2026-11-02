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
    final allHidden = accounts.isNotEmpty && accounts.every((s) => !s.inFeed);
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
            icon: Icon(allHidden ? Icons.visibility : Icons.visibility_off_outlined),
            tooltip: allHidden ? l10n.show_in_main_feed : l10n.hide_from_main_feed,
            onPressed: () => context.read<SubscriptionsModel>().setInFeed(accounts, allHidden),
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
    final removed = await model.unsubscribeAll(selected);
    onClear();
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.n_subscriptions_removed(removed.subscriptions.length)),
      action: SnackBarAction(label: l10n.undo, onPressed: () => model.restore(removed)),
    ));
  }
}

enum _SheetResult { done, newGroup }

Future<void> showGroupsSheet(BuildContext context, List<Subscription> selected, {required VoidCallback onDone}) async {
  final result = await showModalBottomSheet<_SheetResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupsSheet(selected: selected),
  );
  if (context.mounted) {
    await context.read<GroupsModel>().reloadGroups();
  }
  final saved = result == _SheetResult.newGroup &&
      context.mounted &&
      await openGroupEditor(context, initialMembers: selected.map((s) => s.id).toSet());
  if (result == _SheetResult.done || saved) {
    onDone();
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
                      onPressed: () => Navigator.pop(context, _SheetResult.newGroup),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.new_group),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context, _SheetResult.done), child: Text(l10n.done)),
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
    final l10n = L10n.of(context);
    final ids = selected.map((s) => s.id).toList();
    final inGroup = ids.where(members.contains).length;
    final all = inGroup == ids.length;
    final tone = groupTone(context, group.color);
    return CheckboxListTile(
      tristate: true,
      value: all ? true : (inGroup == 0 ? false : null),
      secondary: CircleAvatar(
        backgroundColor: tone.background,
        child: Icon(group.iconData, color: tone.foreground, size: 22),
      ),
      title: Text(group.name),
      subtitle: Text(all
          ? l10n.whole_selection_in_group
          : inGroup == 0
              ? membersSummary(context, context.read<SubscriptionsModel>().state.where((s) => members.contains(s.id)))
              : l10n.part_of_selection_in_group(inGroup, ids.length)),
      onChanged: (_) async {
        final groups = context.read<GroupsModel>();
        final memberships = context.read<GroupMembershipsModel>();
        await (all
            ? groups.removeMembers(group.id, ids)
            : groups.addMembers(group.id, ids.where((id) => !members.contains(id))));
        await memberships.reload();
      },
    );
  }
}
