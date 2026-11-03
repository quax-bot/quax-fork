const int additionalRandomNumber = 3;
const String defaultKeyword = 'obfiowerehiring';

final RegExp indicesRegex = RegExp(
  r'(\(\w{1}\[(\d{1,2})\],\s*16\))+',
  multiLine: true,
);

final RegExp entryScriptRegex = RegExp(
  r'''["'](https://abs\.twimg\.com/[^"']+/entry-client[\w-]*\.js)["']''',
);

/// The entry script imports a few bindings from each of the bundles it starts
/// with, one of which lazily imports the sign module. X names them by a bare
/// hash, so they are told apart by how they are imported.
final RegExp signImporterRegex = RegExp(
  r'''import\{[^}]*,[^}]*\}from["']([./\w-]+\.js)["']''',
);

final RegExp signFileRegex = RegExp(
  r'''import\(["'`]([./\w-]+\.js)["'`]\)\.then\(\(?(\w+)\)?=>\2\.default\(\)\)''',
);
