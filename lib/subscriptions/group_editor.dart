import 'dart:convert';

import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';
import 'package:flutter_triple/flutter_triple.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/_groups.dart';
import 'package:quax/subscriptions/_list.dart';
import 'package:quax/subscriptions/group_editor_model.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscriptions_page_model.dart';
import 'package:quax/subscriptions/users_model.dart';

const _palette = <Color>[
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.indigo,
  Colors.blue,
  Colors.teal,
  Colors.green,
  Colors.amber,
  Colors.orange,
  Colors.brown,
  Colors.blueGrey,
];

final _quickIcons = [
  defaultGroupIcon,
  ...['memory', 'newspaper', 'sports_soccer', 'photo_camera', 'palette', 'science', 'music_note', 'sports_esports', 'public']
      .map((key) => jsonEncode({'pack': 'material', 'key': key})),
];

/// A new group starts with [initialMembers].
Future<void> openGroupEditor(BuildContext context, {String? id, Set<String> initialMembers = const {}}) =>
    Navigator.push(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => GroupEditorScreen(id: id, initialMembers: initialMembers)),
    );

class GroupEditorScreen extends StatefulWidget {
  final String? id;
  final Set<String> initialMembers;

  const GroupEditorScreen({super.key, required this.id, required this.initialMembers});

  @override
  State<GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends State<GroupEditorScreen> {
  late final GroupEditorModel _model = GroupEditorModel(context.read<GroupsModel>());
  final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _model.load(widget.id, widget.initialMembers).then((_) => _name.text = _model.state?.draft.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _model.destroy();
    super.dispose();
  }

  Future<void> _save() async {
    if (await _model.save() && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<GroupEditorModel, GroupEditorState?>(
      store: _model,
      onState: (_, state) {
        if (state == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return PopScope(
          canPop: !state.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop && await _confirmDiscard(context) && context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: _appBar(context, state),
            body: _GroupEditorBody(model: _model, state: state, nameController: _name),
          ),
        );
      },
    );
  }

  AppBar _appBar(BuildContext context, GroupEditorState state) {
    final l10n = L10n.of(context);
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), tooltip: l10n.close, onPressed: () => Navigator.maybePop(context)),
      title: Text(state.draft.id == null ? l10n.new_group : state.original.name),
      actions: [
        FilledButton(onPressed: _save, child: Text(l10n.save)),
        if (state.draft.id == null)
          const SizedBox(width: 12)
        else
          PopupMenuButton<void>(
            tooltip: l10n.more_options,
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _delete(context, state.draft.name),
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  title: Text(l10n.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, String name) async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.are_you_sure),
        content: Text(l10n.are_you_sure_you_want_to_delete_the_subscription_group_name_of_group(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _model.delete();
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}

Future<bool> _confirmDiscard(BuildContext context) async {
  final l10n = L10n.of(context);
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.discard_changes),
      content: Text(l10n.discard_changes_description),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.keep_editing)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.discard)),
      ],
    ),
  );
  return discard ?? false;
}

class _GroupEditorBody extends StatelessWidget {
  final GroupEditorModel model;
  final GroupEditorState state;
  final TextEditingController nameController;

  const _GroupEditorBody({required this.model, required this.state, required this.nameController});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final subscriptions = [...context.read<SubscriptionsModel>().state]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final query = state.query.trim().toLowerCase();
    final searched = subscriptions.where((s) => matchesQuery(s, query)).toList();
    final shown = searched.where((s) => state.kind == null || SubscriptionKind.of(s) == state.kind).toList();
    // The members of the group as it opened stay first, so that ticking a box never moves a row
    final wereIn = shown.where((s) => state.original.members.contains(s.id)).toList();
    final others = shown.where((s) => !state.original.members.contains(s.id)).toList();
    final members = subscriptions.where((s) => state.draft.members.contains(s.id));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Identity(model: model, state: state, nameController: nameController)),
        const SliverToBoxAdapter(child: Divider(indent: 16, endIndent: 16, height: 32)),
        SliverToBoxAdapter(
          child: ListTile(
            title: Text(l10n.members, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(membersSummary(context, members)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: l10n.search_your_subscriptions,
              leading: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.search)),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: model.search,
            ),
          ),
        ),
        SliverToBoxAdapter(child: KindFilters(searched: searched, chosen: state.kind, onChosen: model.showKind)),
        ..._section(context, l10n.in_the_group, wereIn),
        ..._section(context, l10n.other_subscriptions, others),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
      ],
    );
  }

  List<Widget> _section(BuildContext context, String title, List<Subscription> subscriptions) {
    if (subscriptions.isEmpty) {
      return const [];
    }
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ),
      ),
      SliverList.builder(
        itemCount: subscriptions.length,
        itemBuilder: (_, index) {
          final subscription = subscriptions[index];
          return CheckboxListTile(
            key: ValueKey(subscriptionKey(subscription)),
            secondary: SubscriptionAvatar(subscription: subscription),
            title: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              subscription is UserSubscription ? '@${subscription.screenName}' : L10n.of(context).search_term,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: state.draft.members.contains(subscription.id),
            onChanged: (_) => model.toggleMember(subscription.id),
          );
        },
      ),
    ];
  }
}

class _Identity extends StatelessWidget {
  final GroupEditorModel model;
  final GroupEditorState state;
  final TextEditingController nameController;

  const _Identity({required this.model, required this.state, required this.nameController});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tone = groupTone(context, state.draft.color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: tone.background, borderRadius: BorderRadius.circular(20)),
                child: Icon(deserializeIconData(state.draft.icon), size: 32, color: tone.foreground),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: nameController,
                  onChanged: model.rename,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.name,
                    border: const OutlineInputBorder(),
                    errorText: state.showNameError ? l10n.please_enter_a_name : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Label(l10n.color),
          _ColorChoices(selected: state.draft.color, onPicked: model.pickColor),
          const SizedBox(height: 16),
          _Label(l10n.icon),
          _IconChoices(selected: state.draft.icon, tone: tone, onPicked: model.pickIcon),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

class _ColorChoices extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color?> onPicked;

  const _ColorChoices({required this.selected, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = <Color?>[
      null,
      ..._palette,
      if (selected != null && !_palette.any((c) => c.toARGB32() == selected!.toARGB32())) selected,
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: palette.indexed.map((entry) {
          final (index, color) = entry;
          final tone = groupTone(context, color);
          final isSelected = color?.toARGB32() == selected?.toARGB32();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: color == null ? l10n.default_color : '${l10n.color} $index',
              child: InkResponse(
                onTap: () => onPicked(color),
                radius: 24,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tone.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? tone.foreground : Colors.transparent, width: 2),
                  ),
                  child: isSelected ? Icon(Icons.check, size: 20, color: tone.foreground) : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IconChoices extends StatelessWidget {
  final String selected;
  final GroupTone tone;
  final ValueChanged<String> onPicked;

  const _IconChoices({required this.selected, required this.tone, required this.onPicked});

  Future<void> _pickAnother(BuildContext context) async {
    final l10n = L10n.of(context);
    final icon = await showIconPicker(
      context,
      configuration: SinglePickerConfiguration(
        iconPackModes: [IconPack.material],
        title: Text(l10n.pick_an_icon),
        closeChild: Text(l10n.close),
        searchHintText: l10n.search,
        noResultsText: l10n.no_results_for,
      ),
    );
    if (icon != null) {
      onPicked(jsonEncode(serializeIcon(icon)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icons = [if (!_quickIcons.contains(selected)) selected, ..._quickIcons];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...icons.indexed.map((entry) {
            final (index, icon) = entry;
            final isSelected = icon == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                isSelected: isSelected,
                style: IconButton.styleFrom(
                  backgroundColor: isSelected ? tone.background : colors.surfaceContainerHigh,
                  foregroundColor: isSelected ? tone.foreground : colors.onSurfaceVariant,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  fixedSize: const Size(48, 48),
                ),
                icon: Icon(deserializeIconData(icon), semanticLabel: '${L10n.of(context).icon} ${index + 1}'),
                onPressed: () => onPicked(icon),
              ),
            );
          }),
          IconButton.outlined(
            tooltip: L10n.of(context).pick_an_icon,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              fixedSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _pickAnother(context),
          ),
        ],
      ),
    );
  }
}
