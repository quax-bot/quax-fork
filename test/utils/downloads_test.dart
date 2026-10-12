import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pref/pref.dart';
import 'package:quax/constants.dart';
import 'package:quax/utils/downloads.dart';

const _sdCardFolder = 'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AQuaX';

class _StorageSpy {
  final List<MethodCall> storageCalls = [];
  final List<MethodCall> dialogCalls = [];

  _StorageSpy() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('browser_resolver'), (call) async {
      storageCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_file_dialog'), (call) async {
      dialogCalls.add(call);
      return '/picked/by/user.png';
    });
  }
}

BasePrefService _prefs(String downloadType, String downloadPath) =>
    PrefServiceCache(defaults: {optionDownloadType: downloadType, optionDownloadPath: downloadPath});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final media = Uint8List.fromList([1, 2, 3]);

  group('saveDownloadedMedia()', () {
    test('Should write through the folder the user granted, so that a SD card folder works', () async {
      final spy = _StorageSpy();

      final saved = await saveDownloadedMedia(_prefs(optionDownloadTypeDirectory, _sdCardFolder), 'cat.png', media);

      expect(saved, isTrue, reason: 'The media was written, so the download should be reported as a success');
      expect(spy.storageCalls.map((call) => call.method), ['saveToDirectory'],
          reason: 'Android only lets QuaX write on a SD card through the folder the user granted');
      expect(spy.storageCalls.single.arguments,
          {'directoryUri': _sdCardFolder, 'fileName': 'cat.png', 'data': media},
          reason: 'The media should land in the chosen folder under its own name');
      expect(spy.dialogCalls, isEmpty, reason: 'A download folder is set, so no save dialog should open');
    });

    test('Should ask where to save when the folder was stored as a plain path by an older version', () async {
      final spy = _StorageSpy();

      final saved = await saveDownloadedMedia(
          _prefs(optionDownloadTypeDirectory, '/storage/1A2B-3C4D/QuaX'), 'cat.png', media);

      expect(saved, isTrue, reason: 'The user picked a place in the dialog, so the download succeeded');
      expect(spy.dialogCalls.map((call) => call.method), ['saveFile'],
          reason: 'A plain path cannot be written to on a SD card, so the system save dialog should open instead');
      expect(spy.storageCalls, isEmpty, reason: 'There is no granted folder to write to');
    });

    test('Should ask where to save when the user chose to always be asked', () async {
      final spy = _StorageSpy();

      await saveDownloadedMedia(_prefs(optionDownloadTypeAsk, _sdCardFolder), 'cat.png', media);

      expect(spy.dialogCalls.map((call) => call.method), ['saveFile'],
          reason: 'The "Always ask" setting wins over a folder chosen earlier');
      expect(spy.storageCalls, isEmpty, reason: 'The chosen folder should be ignored with "Always ask"');
    });
  });

  group('downloadDirectoryLabel()', () {
    test('Should show the volume and the folder of the granted folder', () {
      expect(downloadDirectoryLabel(_sdCardFolder), '1A2B-3C4D:QuaX',
          reason: 'The settings should show a readable folder, not an encoded content URI');
    });
  });
}
