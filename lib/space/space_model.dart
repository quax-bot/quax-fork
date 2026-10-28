import 'package:flutter_triple/flutter_triple.dart';
import 'package:quax/client/client.dart';
import 'package:quax/space/space.dart';

class SpaceModel extends Store<Space> {
  final String id;

  SpaceModel(this.id) : super(Space(id: id, title: '', state: SpaceState.scheduled));

  Future<void> load() => execute(() => Twitter.getSpace(id));
}

class SpacePlaylistModel extends Store<String> {
  final String mediaKey;

  SpacePlaylistModel(this.mediaKey) : super('');

  Future<void> load() => execute(() => Twitter.getSpacePlaylist(mediaKey));
}
