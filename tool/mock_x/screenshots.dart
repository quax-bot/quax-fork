import 'dart:io';

/// The adb arguments that show the status bar of a phone at rest, the same on every run: noon, full battery
/// and signal, and no notification icon.
const statusBarAtRest = [
  ['shell', 'settings', 'put', 'global', 'sysui_demo_allowed', '1'],
  ['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'enter'],
  ['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'clock', '-e', 'hhmm', '1200'],
  [
    ...['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'battery'],
    ...['-e', 'level', '100', '-e', 'plugged', 'false'],
  ],
  [
    ...['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'network'],
    ...['-e', 'wifi', 'show', '-e', 'level', '4', '-e', 'mobile', 'hide'],
  ],
  [
    ...['shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'notifications'],
    ...['-e', 'visible', 'false'],
  ],
];

/// The screenshots the takeScreenshot commands of the flows wrote in Maestro's debug output [folder], by
/// the path each command gave. Maestro puts them in a takeScreenshot folder of the flow's own output.
Map<String, File> takenScreenshots(Directory folder) => {
  for (final file in folder.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.png') && file.uri.pathSegments.contains(_folder)) _pathInFolder(file): file,
};

const _folder = 'takeScreenshot';

String _pathInFolder(File file) {
  final segments = file.uri.pathSegments;
  return segments.skip(segments.lastIndexOf(_folder) + 1).join('/');
}
