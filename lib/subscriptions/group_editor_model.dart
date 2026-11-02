import 'package:flutter_triple/flutter_triple.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quax/database/entities.dart';
import 'package:quax/group/group_model.dart';
import 'package:quax/subscriptions/subscription_kind.dart';
import 'package:quax/subscriptions/subscription_order.dart';

class GroupDraft {
  final String? id;
  final String name;
  final String icon;
  final Color? color;
  final Set<String> members;

  const GroupDraft({required this.id, required this.name, required this.icon, required this.color, required this.members});

  factory GroupDraft.of(SubscriptionGroupEdit group) =>
      GroupDraft(id: group.id, name: group.name, icon: group.icon, color: group.color, members: {...group.members});

  GroupDraft copyWith({String? name, String? icon, Color? Function()? color, Set<String>? members}) => GroupDraft(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color == null ? this.color : color(),
        members: members ?? this.members,
      );

  bool sameAs(GroupDraft other) =>
      name == other.name &&
      icon == other.icon &&
      color?.toARGB32() == other.color?.toARGB32() &&
      members.length == other.members.length &&
      members.containsAll(other.members);
}

class GroupEditorState {
  final GroupDraft original;
  final GroupDraft draft;

  /// Every subscription, by name.
  final List<Subscription> subscriptions;
  final String query;
  final SubscriptionKind? kind;
  final bool showNameError;
  final bool closing;

  const GroupEditorState(
      {required this.original,
      required this.draft,
      required this.subscriptions,
      this.query = '',
      this.kind,
      this.showNameError = false,
      this.closing = false});

  bool get dirty => !draft.sameAs(original);

  GroupEditorState copyWith(
          {GroupDraft? draft, String? query, SubscriptionKind? Function()? kind, bool? showNameError, bool? closing}) =>
      GroupEditorState(
        original: original,
        draft: draft ?? this.draft,
        subscriptions: subscriptions,
        query: query ?? this.query,
        kind: kind == null ? this.kind : kind(),
        showNameError: showNameError ?? this.showNameError,
        closing: closing ?? this.closing,
      );
}

/// Null until the group is loaded.
class GroupEditorModel extends Store<GroupEditorState?> {
  final GroupsModel groups;

  GroupEditorModel(this.groups) : super(null);

  /// A new group starts with [initialMembers]. The caller shows the result, if still open.
  Future<GroupEditorState> load(String? id, Set<String> initialMembers, List<Subscription> subscriptions) async {
    final group = GroupDraft.of(await groups.loadGroupEdit(id));
    final draft = id == null ? group.copyWith(members: initialMembers) : group;
    return GroupEditorState(
        original: draft, draft: draft, subscriptions: [...subscriptions]..sort(compareNames));
  }

  void _edit(GroupEditorState Function(GroupEditorState state) change) {
    final current = state;
    if (current != null) {
      update(change(current));
    }
  }

  void rename(String name) => _edit((s) => s.copyWith(draft: s.draft.copyWith(name: name), showNameError: false));

  void pickIcon(String icon) => _edit((s) => s.copyWith(draft: s.draft.copyWith(icon: icon)));

  void pickColor(Color? color) => _edit((s) => s.copyWith(draft: s.draft.copyWith(color: () => color)));

  void search(String query) => _edit((s) => s.copyWith(query: query));

  void showKind(SubscriptionKind? kind) => _edit((s) => s.copyWith(kind: () => kind));

  void toggleMember(String id) => _edit((s) {
        final members = s.draft.members.contains(id) ? (s.draft.members.toSet()..remove(id)) : {...s.draft.members, id};
        return s.copyWith(draft: s.draft.copyWith(members: members));
      });

  /// Returns false when the group has no name, or is already closing.
  Future<bool> save() async {
    final current = state;
    if (current == null || current.closing) {
      return false;
    }
    final name = current.draft.name.trim();
    if (name.isEmpty) {
      update(current.copyWith(showNameError: true));
      return false;
    }
    update(current.copyWith(closing: true));
    final draft = current.draft;
    await groups.saveGroup(draft.id, name, draft.icon, draft.color, draft.members);
    return true;
  }

  Future<void> delete() async {
    final current = state;
    final id = current?.draft.id;
    if (current != null && id != null) {
      update(current.copyWith(closing: true));
      await groups.deleteGroup(id);
    }
  }
}
