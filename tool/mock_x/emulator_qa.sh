#!/usr/bin/env bash
# Installs an APK built with --dart-define=QUAX_MOCK_X=http://localhost:8787 on the running
# emulator and runs each Maestro flow of a folder against the mock of X (tool/mock_x/server.dart,
# already running and logging to <mock log>), recording one video per flow.
# Fails when a flow fails or the mock of X answered nothing.
#
#   tool/mock_x/emulator_qa.sh <apk> <flows folder> <mock log> <output dir>

set -euo pipefail

APK=$1
FLOWS=$2
MOCK_LOG=$3
OUT=$4
AAPT2=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)/aapt2
PACKAGE=$("$AAPT2" dump packagename "$APK")

mkdir -p "$OUT"

# Links are only followed once past the onboarding, and the launch dialogs would hide the screens
skip_onboarding() {
  local prefs
  prefs=$(mktemp)
  cat > "$prefs" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="flutter.pref_onboarding.done" value="true" />
    <boolean name="flutter.pref_discord_popup.dismissed" value="true" />
    <boolean name="flutter.pref_should_check_for_updates" value="false" />
</map>
EOF
  adb push "$prefs" /data/local/tmp/quax_prefs.xml
  adb shell "cat /data/local/tmp/quax_prefs.xml | run-as $PACKAGE sh -c 'mkdir -p shared_prefs && cat > shared_prefs/FlutterSharedPreferences.xml'"
}

# x.com links must open QuaX rather than Chrome, and no system dialog must cover the app when the
# overloaded emulator reports a slow app
prepare_device() {
  adb shell pm disable-user --user 0 com.android.chrome
  adb shell pm set-app-links-user-selection --user 0 --package "$PACKAGE" true x.com
  adb shell settings put global hide_error_dialogs 1
}

# trim_start <video>: cuts the still frames shown while Maestro starts, up to half a second
# before the screen first changes
trim_start() {
  local start
  if ! command -v ffmpeg > /dev/null; then
    echo "::warning::ffmpeg is missing, the videos keep Maestro's start-up"
    return 0
  fi
  start=$(ffmpeg -i "$1" -vf "select='gt(scene,0.2)',showinfo" -f null - 2>&1 \
    | grep -m1 -o 'pts_time:[0-9.]*' | cut -d: -f2)
  [ -n "$start" ] || return 0
  ffmpeg -v error -y -ss "$(echo "$start" | awk '{ print ($1 > 0.5) ? $1 - 0.5 : 0 }')" -i "$1" \
    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$1.trimmed.mp4"
  mv "$1.trimmed.mp4" "$1"
}

# record <name> <command...>: runs the command while recording the screen to <output dir>/<name>.mp4
record() {
  local name=$1 status=0
  shift
  adb shell screenrecord --bit-rate 8000000 "/sdcard/$name.mp4" &
  sleep 1
  "$@" || status=$?
  adb shell pkill -INT screenrecord || true
  sleep 3
  adb pull "/sdcard/$name.mp4" "$OUT/$name.mp4" && trim_start "$OUT/$name.mp4" || true
  return $status
}

check_mock() {
  local unmatched
  unmatched=$(grep -c '^501 ' "$MOCK_LOG" || true)
  if [ "$unmatched" -gt 0 ]; then
    echo "::warning::The mock of X could not answer $unmatched request(s), see mock_x.log"
  fi
  if ! grep -q '^200 ' "$MOCK_LOG"; then
    echo "::error::The mock of X answered no request, the app did not reach it"
    return 1
  fi
}

adb wait-for-device
adb reverse tcp:8787 tcp:8787
adb install -r "$APK"
skip_onboarding
prepare_device
adb logcat -c

failed=0
for flow in "$FLOWS"/*.yaml; do
  name=$(basename "$flow" .yaml)
  record "$name" maestro test --debug-output "$OUT/maestro/$name" "$flow" || failed=1
done

adb logcat -d > "$OUT/logcat.txt"
check_mock || failed=1
exit $failed
