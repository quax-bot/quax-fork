import 'package:flutter_triple/flutter_triple.dart';
import 'package:quax/client/client.dart';
import 'package:quax/space/space.dart';

class SpaceModel extends Store<Space> {
  // A feed rebuilds a card each time it scrolls back into view: a space already loaded then shows at once
  static final Map<String, Space> _loaded = {};

  final String id;

  SpaceModel(this.id) : super(_loaded[id] ?? Space(id: id, title: '', state: SpaceState.scheduled));

  Future<void> load() => execute(() async => _loaded[id] = await Twitter.getSpace(id));

  Future<void> loadOnce() async => _loaded.containsKey(id) ? null : load();
}

class SpacePlaylistModel extends Store<String> {
  final String mediaKey;

  SpacePlaylistModel(this.mediaKey) : super('');

  Future<void> load() => execute(() => Twitter.getSpacePlaylist(mediaKey));
}
