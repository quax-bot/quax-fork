import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'package:quax/constants.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/ui/errors.dart';
import 'package:http/http.dart' as http;
import 'package:pref/pref.dart';

Future<void> downloadUriToPickedFile(BuildContext context, Uri uri, String fileName,
    {required BasePrefService prefs, required Function() onStart, required Function() onSuccess}) async {
  var sanitizedFilename = fileName.split("?")[0];

  try {
    onStart();
    var responseTask = downloadFile(context, uri);

    var response = await responseTask;
    if (response == null) {
      return;
    }

    if (await saveDownloadedMedia(prefs, sanitizedFilename, response)) {
      onSuccess();
    }
  } catch (e) {
    if (context.mounted) {
      showSnackBar(context, icon: '🙊', message: e.toString());
    }
  }
}

const _storageChannel = MethodChannel('browser_resolver');

bool isDownloadDirectoryUri(String path) => path.startsWith('content://');

String downloadDirectoryLabel(String directoryUri) => Uri.decodeComponent(directoryUri.split('/').last);

Future<String?> pickDownloadDirectory() => _storageChannel.invokeMethod<String>('pickDownloadDirectory');

Future<bool> saveDownloadedMedia(BasePrefService prefs, String fileName, Uint8List data) async {
  final String downloadPath = prefs.get(optionDownloadPath) ?? '';
  if (prefs.get(optionDownloadType) == optionDownloadTypeAsk || !isDownloadDirectoryUri(downloadPath)) {
    final savedPath = await FlutterFileDialog.saveFile(params: SaveFileDialogParams(fileName: fileName, data: data));
    return savedPath != null;
  }

  await _storageChannel
      .invokeMethod('saveToDirectory', {'directoryUri': downloadPath, 'fileName': fileName, 'data': data});
  return true;
}

class UnableToSaveMedia {
  final Uri uri;
  final Object e;

  UnableToSaveMedia(this.uri, this.e);

  @override
  String toString() {
    return 'Unable to save the media {uri: $uri, e: $e}';
  }
}

Future downloadFile(BuildContext context, Uri uri) async {
  var response = await http.get(uri);
  if (response.statusCode == 200) {
    return response.bodyBytes;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        L10n.of(context).unable_to_save_the_media_twitter_returned_a_status_of_response_statusCode(response.statusCode),
      ),
    ));
  }

  return null;
}
