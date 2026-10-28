import 'package:flutter_triple/flutter_triple.dart';
import 'package:quax/client/client.dart';
import 'package:quax/space/space.dart';

class SpaceModel extends Store<Space> {
  final String id;

  SpaceModel(this.id) : super(Space(id: id, title: '', state: SpaceState.scheduled));

  Future<void> load() => execute(() => Twitter.getSpace(id));
}
