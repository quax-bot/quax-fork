// Set by tool/update_chrome.py at each release. To bump Chrome by hand, run it or change only this line.
const chromeFullVersion = '157.0.8103.78';

// Chrome freezes everything but its major version in its user agent
final chromeUserAgent = chromeUserAgentOf(chromeFullVersion);

String chromeUserAgentOf(String fullVersion) =>
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${_majorOf(fullVersion)}.0.0.0 Mobile Safari/537.36';

/// Sent with every request to X, so that all of them look like the Chrome on Android that logged in.
final Map<String, String> chromeHeaders = Map.unmodifiable({
  'user-agent': chromeUserAgent,
  'sec-ch-ua': chromeSecChUa(chromeFullVersion),
  'sec-ch-ua-mobile': '?1',
  'sec-ch-ua-platform': '"Android"',
});

typedef ChromeBrand = ({String name, String majorVersion, String fullVersion});

String chromeSecChUa(String fullVersion) =>
    chromeBrands(fullVersion).map((brand) => '"${brand.name}";v="${brand.majorVersion}"').join(', ');

/// The brands of Chrome's `sec-ch-ua`, in the order of `GenerateBrandVersionList()` in Chromium's
/// `components/embedder_support/user_agent_utils.cc`.
List<ChromeBrand> chromeBrands(String fullVersion) {
  // order[i] is the slot of brands[i]
  const brandOrders = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ];

  final major = _majorOf(fullVersion);
  final brands = [
    _greaseBrand(major),
    (name: 'Chromium', majorVersion: '$major', fullVersion: fullVersion),
    (name: 'Google Chrome', majorVersion: '$major', fullVersion: fullVersion),
  ];
  final order = brandOrders[major % brandOrders.length];
  return List.generate(brands.length, (slot) => brands[order.indexOf(slot)]);
}

/// The fake brand Chrome adds so that servers do not rely on the list, e.g. "Not_A Brand".
ChromeBrand _greaseBrand(int major) {
  const characters = [' ', '(', ':', '-', '.', '/', ')', ';', '=', '?', '_'];
  const versions = ['8', '99', '24'];

  final version = versions[major % versions.length];
  return (
    name: 'Not${characters[major % characters.length]}A${characters[(major + 1) % characters.length]}Brand',
    majorVersion: version,
    fullVersion: '$version.0.0.0',
  );
}

int _majorOf(String fullVersion) => int.parse(fullVersion.split('.').first);
