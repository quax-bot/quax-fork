import 'package:flutter_test/flutter_test.dart';
import 'package:quax/tweet/_video_controls.dart';

void main() {
  test('Should offer speeds above 2x', () {
    expect(videoPlaybackSpeeds, containsAll([2.5, 3.0, 4.0]),
        reason: 'The playback speed menu should go beyond 2x, up to 4x, for long videos watched fast');
  });

  test('Should list the speeds from the slowest to the fastest', () {
    expect(videoPlaybackSpeeds, [...videoPlaybackSpeeds]..sort(),
        reason: 'The menu shows the speeds in reverse, so the fastest should be last for it to come on top');
  });
}
