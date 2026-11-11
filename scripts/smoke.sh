#!/bin/bash
# End-to-end smoke test through the debug URL (docs/ROADMAP.md › Verification).
# Needs Screen Recording permission for shotX and `defaults write local.shotx.app debugURL -bool true`.
# Rebuilds and relaunches build/shotX.app. Side effects: the screen is captured and recorded, the
# clipboard is replaced, Quick Access cards appear. The files it creates are deleted when it passes.
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN=local.shotx.app
APP="$PWD/build/shotX.app"

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }
pref() { defaults read "$DOMAIN" "$1" 2>/dev/null || echo "$2"; }

[ "$(pref debugURL 0)" = 1 ] || fail "debug URL is off; run: defaults write $DOMAIN debugURL -bool true"
[ "$(pref saveAfterCapture 1)" = 1 ] || fail "turn on saving after capture in Settings"
[ "$(pref imageFormat png)" = png ] || fail "set the image format to PNG in Settings"
[ "$(pref recordingFormat mp4)" = mp4 ] || fail "set the recording format to MP4 in Settings"
DIR="$(pref saveDirectory "$HOME/Pictures/shotX")"

# Pixel size of every screen ("WxH@scale", primary first), as DisplaySnapshot sees it: frame × scale.
SCREENS="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens, r = [];
for (var i = 0; i < s.count; i++) { var o = s.objectAtIndex(i), k = o.backingScaleFactor;
r.push((o.frame.size.width * k) + "x" + (o.frame.size.height * k) + "@" + k) } r.join(" ")')"
PRIMARY_SCALE="${SCREENS%% *}"; PRIMARY_SCALE="${PRIMARY_SCALE##*@}"

pixel_size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/ {w = $2} /pixelHeight/ {h = $2} END {print w "x" h}'; }
movie_seconds() {
    swift - "$1" <<'EOF'
import AVFoundation
print(try await AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1])).load(.duration).seconds)
EOF
}

CREATED=()
send() { open -a "$APP" "shotx://$1"; }
snapshot() { BEFORE="$(ls "$DIR"/* 2>/dev/null || true)"; }
# Waits up to $2 s for a .$1 file that was not in the last snapshot, then prints its path.
new_file() {
    for ((i = 0; i < $2 * 2; i++)); do
        local f
        f="$(ls -t "$DIR"/*."$1" 2>/dev/null | head -1 || true)"
        if [ -n "$f" ] && ! grep -qxF "$f" <<< "$BEFORE"; then echo "$f"; return; fi
        sleep 0.5
    done
    fail "no new .$1 in $DIR after $2 s (Screen Recording permission? Console: subsystem $DOMAIN)"
}

echo "smoke: building and relaunching $APP"
scripts/bundle.sh > /dev/null
pkill -x shotX || true
while pgrep -x shotX > /dev/null; do sleep 0.2; done
open "$APP"
sleep 2
# ponytail: fixed sleeps around app launch and the coordinator's busy gate; poll the log if they flake.

snapshot; send captureFullscreen
f="$(new_file png 15)"; CREATED+=("$f")
size="$(pixel_size "$f")"
[[ " $SCREENS" == *" $size@"* ]] || fail "fullscreen is $size, expected one of: $SCREENS"
echo "smoke: captureFullscreen ok ($size)"
sleep 1

snapshot; send "capture-area?x=100&y=100&w=300&h=200"
f="$(new_file png 15)"; CREATED+=("$f")
size="$(pixel_size "$f")"
expected="$((300 * PRIMARY_SCALE))x$((200 * PRIMARY_SCALE))"
[ "$size" = "$expected" ] || fail "capture-area is $size, expected $expected"
echo "smoke: capture-area ok ($size)"
sleep 1

snapshot; send toggleRecording
sleep 4
send toggleRecording
f="$(new_file mp4 20)"; CREATED+=("$f")
seconds="$(movie_seconds "$f")"
awk -v s="$seconds" 'BEGIN { exit !(s > 2) }' || fail "recording is $seconds s, expected more than 2"
echo "smoke: recording ok (${seconds} s)"

rm -f "${CREATED[@]}"
echo "smoke OK"
