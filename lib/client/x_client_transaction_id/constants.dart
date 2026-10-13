const int additionalRandomNumber = 3;
const String defaultKeyword = 'obfiowerehiring';

final RegExp indicesRegex = RegExp(
  r'(\(\w{1}\[(\d{1,2})\],\s*16\))+',
  multiLine: true,
);

const String scriptsHost = 'abs.twimg.com';

/// A quoted path to a script, absolute or relative to the file it is in.
final RegExp scriptPathRegex = RegExp(
  r'''["'`]((?:https://abs\.twimg\.com/|\.{0,2}/)[\w./-]*\.js)["'`]''',
);

/// The webpack build of x.com, before September 2026, listed its chunks by index.
final RegExp legacyOndemandIndexRegex = RegExp(r''',(\d+):["']ondemand\.s["']''');

const String legacyOndemandUrlTemplate = 'https://abs.twimg.com/responsive-web/client-web/ondemand.s.{hash}a.js';

/// How much each hint in a script name raises its chance to lead to the sign
/// module. Only decides the order of the downloads: the content decides.
final Map<RegExp, int> signModuleNameHints = {
  RegExp(r'(^|[^a-z])sign([^a-z]|$)'): 4,
  RegExp('transaction'): 2,
  RegExp('ondemand'): 2,
  RegExp('^(entry|main)'): 1,
};

/// Downloads allowed to find the sign module, and how many run at once.
const int signModuleSearchBudget = 40;
const int signModuleSearchWave = 8;
