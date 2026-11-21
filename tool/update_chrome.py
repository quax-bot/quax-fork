"""Sets chromeFullVersion in lib/client/chrome.dart to the Chrome build most Android users run.

Run: python3 tool/update_chrome.py
A failure only prints a warning, so the QuaX release still goes on with the Chrome version already in the code.
"""

import collections
import json
import pathlib
import re
import urllib.request

# https://developer.chrome.com/docs/web-platform/versionhistory/guide
LIVE_RELEASES_URL = (
    "https://versionhistory.googleapis.com/v1/chrome/platforms/android/channels/stable/versions/all/releases"
    "?filter=endtime=none"
)
CHROME_DART_PATH = pathlib.Path(__file__).parent.parent / "lib" / "client" / "chrome.dart"
FULL_VERSION_LINE = re.compile(r"const chromeFullVersion = '[\d.]+';")
FULL_VERSION = re.compile(r"^\d+\.\d+\.\d+\.\d+$")


def major_of(version: str) -> str:
    return version.split(".")[0]


def most_used_full_version() -> str:
    with urllib.request.urlopen(LIVE_RELEASES_URL, timeout=30) as response:
        releases = json.load(response)["releases"]
    # Fractions only add up within a group, and the newest group is the current rollout
    newest_group = max(int(release["fractionGroup"]) for release in releases)
    rollout = [release for release in releases if int(release["fractionGroup"]) == newest_group]
    share_by_major = collections.Counter()
    for release in rollout:
        share_by_major[major_of(release["version"])] += release.get("fraction", 0)
    major = share_by_major.most_common(1)[0][0]
    releases_of_major = [release for release in rollout if major_of(release["version"]) == major]
    return max(releases_of_major, key=lambda release: release.get("fraction", 0))["version"]


def main() -> None:
    try:
        full_version = most_used_full_version()
        if not FULL_VERSION.match(full_version):
            raise ValueError(f"unexpected Chrome version {full_version!r}")
        source = CHROME_DART_PATH.read_text()
        if not FULL_VERSION_LINE.search(source):
            raise ValueError(f"no chromeFullVersion in {CHROME_DART_PATH}")
        CHROME_DART_PATH.write_text(FULL_VERSION_LINE.sub(f"const chromeFullVersion = '{full_version}';", source))
        print(f"chromeFullVersion set to {full_version}")
    except Exception as error:
        # A GitHub Actions annotation, shown in the summary of the run
        print(f"::warning title=Chrome version not updated::{error}")


if __name__ == "__main__":
    main()
