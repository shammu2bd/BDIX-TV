#!/bin/bash
set -euo pipefail

REPO="shammu2bd/BDIX-TV"
API_PATH="repos/$REPO/contents/Development/output.log"
PROJECT_NAME="RTL88WiFi-1.0.11-WCL-Sequoia-24H32-stage26-clean-source"

fail() {
    echo "ERROR: $*" >&2
    exit 2
}

find_project() {
    if [[ -n "${PROJECT_DIR:-}" ]]; then
        if [[ -f "${PROJECT_DIR}/driver/RTL88WiFi/Makefile" ]]; then
            (cd "${PROJECT_DIR}" && pwd -P)
            return
        fi
        if [[ -f "${PROJECT_DIR}/Makefile" && -d "${PROJECT_DIR}/src/kext" ]]; then
            (cd "${PROJECT_DIR}/../.." && pwd -P)
            return
        fi
        fail "PROJECT_DIR does not identify the Stage26 project or driver directory."
    fi

    local guess="$HOME/Downloads/$PROJECT_NAME"
    [[ -f "$guess/driver/RTL88WiFi/Makefile" ]] || fail "Stage26 project not found at $guess. Set PROJECT_DIR."
    (cd "$guess" && pwd -P)
}

PROJECT="$(find_project)"
DRIVER="$PROJECT/driver/RTL88WiFi"
MAKEFILE="$DRIVER/Makefile"
NATIVE_TEMPLATE="$DRIVER/RTL88WiFiNative.kext"
NATIVE_OUT="$DRIVER/build/out/RTL88WiFiNative.kext"
NATIVE_BIN="$NATIVE_OUT/Contents/MacOS/RTL88WiFiNative"
LOG="$PROJECT/output.log"
STAMP="$(date '+%Y%m%d-%H%M%S')"
STAGE_DIR="$PROJECT/build/stage29c-native-link-build-$STAMP"

mkdir -p "$STAGE_DIR"

# This workflow requires the same authenticated GitHub CLI used by earlier
# autonomous stages. Do not silently leave a report local-only.
command -v gh >/dev/null 2>&1 || fail "GitHub CLI is missing; install gh before running this stage."
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated. Run gh auth login once."

# Start from the canonical GitHub Development log; do not fork/truncate history.
REMOTE_LOG="$STAGE_DIR/output.log.github-before"
gh api "$API_PATH" --jq '.content' | \
    python3 -c 'import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' > "$REMOTE_LOG"
[[ -s "$REMOTE_LOG" ]] || fail "Could not fetch GitHub Development/output.log."
cp "$REMOTE_LOG" "$LOG"

exec > >(tee -a "$LOG") 2>&1

OS_VERSION="$(sw_vers -productVersion)"
OS_BUILD="$(sw_vers -buildVersion)"
ARCH="$(uname -m)"

echo
echo "RTL88WiFi Stage29c — native target actual compile and link"
echo "DATE: $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "PROJECT: $PROJECT"
echo "DRIVER: $DRIVER"
echo "STAGE_DIR: $STAGE_DIR"
echo "HOST: macOS $OS_VERSION / $OS_BUILD / $ARCH"
echo "SCOPE: force-build and link only the separate rtl88wifi-native target."
echo "CANONICAL_LOG: GitHub Development/output.log"
echo "LEGACY_TARGET: NOT INVOKED"
echo "INSTALL: NOT RUN"
echo "LOAD: NOT RUN"
echo "OPENCORE_CHANGE: NONE"
echo "KNOWN_GOOD_LEGACY_KEXT: NOT TOUCHED"

BUILD_RC=0
VERIFY_RC=0

if [[ "$OS_VERSION" != "15.8.1" || "$OS_BUILD" != "24H32" || "$ARCH" != "x86_64" ]]; then
    echo "ERROR: Expected macOS 15.8.1 / 24H32 / x86_64."
    BUILD_RC=10
fi
if [[ "$BUILD_RC" -eq 0 && ! -f "$MAKEFILE" ]]; then
    echo "ERROR: Makefile missing: $MAKEFILE"
    BUILD_RC=11
fi
if [[ "$BUILD_RC" -eq 0 && ! -f "$NATIVE_TEMPLATE/Contents/Info.plist" ]]; then
    echo "ERROR: Native bundle Info.plist missing: $NATIVE_TEMPLATE/Contents/Info.plist"
    BUILD_RC=12
fi
if [[ "$BUILD_RC" -eq 0 ]] && ! grep -Eq '^[[:space:]]*rtl88wifi-native:' "$MAKEFILE"; then
    echo "ERROR: rtl88wifi-native target not found in Makefile."
    BUILD_RC=13
fi

if [[ "$BUILD_RC" -eq 0 ]]; then
    if ! /usr/libexec/PlistBuddy -c 'Print :OSBundleLibraries:com.apple.iokit.IO80211Family' "$NATIVE_TEMPLATE/Contents/Info.plist" >/dev/null 2>&1; then
        echo "ERROR: Native Apple IO80211Family dependency is absent."
        BUILD_RC=14
    fi
    if ! /usr/libexec/PlistBuddy -c 'Print :OSBundleLibraries:com.apple.iokit.IOSkywalkFamily' "$NATIVE_TEMPLATE/Contents/Info.plist" >/dev/null 2>&1; then
        echo "ERROR: Native Apple IOSkywalkFamily dependency is absent."
        BUILD_RC=15
    fi
    if /usr/libexec/PlistBuddy -c 'Print :OSBundleLibraries:com.apple.iokit.IO80211FamilyLegacy' "$NATIVE_TEMPLATE/Contents/Info.plist" >/dev/null 2>&1; then
        echo "ERROR: Legacy IO80211FamilyLegacy dependency must not be in native plist."
        BUILD_RC=16
    fi
fi

if [[ "$BUILD_RC" -eq 0 ]]; then
    echo
    echo "========== CLEAN NATIVE OUTPUT ONLY =========="
    echo "Removing previous experimental build output: $NATIVE_OUT"
    rm -rf "$NATIVE_OUT"

    echo
    echo "========== ACTUAL NATIVE BUILD =========="
    echo "COMMAND: make -B -j1 rtl88wifi-native"
    set +e
    (cd "$DRIVER" && make -B -j1 rtl88wifi-native) 2>&1
    BUILD_RC=$?
    set -e
    echo "NATIVE_BUILD_EXIT: $BUILD_RC"
else
    echo "NATIVE_BUILD_SKIPPED_PREFLIGHT_RC: $BUILD_RC"
fi

if [[ "$BUILD_RC" -eq 0 ]]; then
    echo
    echo "========== NATIVE BUNDLE VALIDATION =========="
    if [[ ! -f "$NATIVE_OUT/Contents/Info.plist" ]]; then
        echo "ERROR: Native output Info.plist was not staged."
        VERIFY_RC=21
    elif [[ ! -f "$NATIVE_BIN" ]]; then
        echo "ERROR: Native executable missing: $NATIVE_BIN"
        VERIFY_RC=22
    else
        plutil -lint "$NATIVE_OUT/Contents/Info.plist" || VERIFY_RC=23
        EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$NATIVE_OUT/Contents/Info.plist")"
        BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$NATIVE_OUT/Contents/Info.plist")"
        echo "BUNDLE_EXECUTABLE: $EXEC_NAME"
        echo "BUNDLE_IDENTIFIER: $BUNDLE_ID"
        [[ "$EXEC_NAME" == "RTL88WiFiNative" ]] || VERIFY_RC=24
        [[ "$BUNDLE_ID" == "io.github.x1ren41l.RTL88WiFi" ]] || VERIFY_RC=25

        echo "NATIVE_BINARY_FILE:"
        file "$NATIVE_BIN"
        echo "NATIVE_ARCHITECTURES:"
        lipo -archs "$NATIVE_BIN"
        ARCHS="$(lipo -archs "$NATIVE_BIN")"
        [[ " $ARCHS " == *" x86_64 "* ]] || VERIFY_RC=26

        echo "NATIVE_MACH_HEADER:"
        otool -hv "$NATIVE_BIN"
        otool -hv "$NATIVE_BIN" | grep -q 'KEXTBUNDLE' || VERIFY_RC=27

        echo "NATIVE_BINARY_SHA256:"
        shasum -a 256 "$NATIVE_BIN"

        echo "NATIVE_DEPENDENCIES:"
        /usr/libexec/PlistBuddy -c 'Print :OSBundleLibraries' "$NATIVE_OUT/Contents/Info.plist"
        if /usr/libexec/PlistBuddy -c 'Print :OSBundleLibraries:com.apple.iokit.IO80211FamilyLegacy' "$NATIVE_OUT/Contents/Info.plist" >/dev/null 2>&1; then
            echo "ERROR: Legacy IO80211 dependency found in built bundle."
            VERIFY_RC=28
        fi
    fi
    echo "NATIVE_POSTBUILD_VERIFY_EXIT: $VERIFY_RC"
else
    echo "NATIVE_POSTBUILD_VERIFY: SKIPPED_BUILD_FAILED"
fi

echo
echo "========== STAGE29C RESULT =========="
if [[ "$BUILD_RC" -eq 0 && "$VERIFY_RC" -eq 0 ]]; then
    echo "NATIVE_ACTUAL_BUILD: PASS"
    echo "NATIVE_BUNDLE_VALIDATION: PASS"
    echo "NEXT_GATE: inspect link symbols and controller/infra registration metadata; do not install/load yet."
else
    echo "NATIVE_ACTUAL_BUILD: FAIL"
    echo "NATIVE_BUILD_EXIT: $BUILD_RC"
    echo "NATIVE_BUNDLE_VERIFY_EXIT: $VERIFY_RC"
    echo "NEXT_GATE: resolve compile/link or bundle validation errors before any further target integration."
fi
echo "LEGACY_TARGET: NOT BUILT OR MODIFIED BY THIS STAGE"
echo "INSTALL: NOT RUN"
echo "LOAD: NOT RUN"
echo "OPENCORE_CHANGE: NONE"
echo "KNOWN_GOOD_LEGACY_KEXT: NOT TOUCHED"
echo "LOCAL_LOG_COPY: $LOG"
echo "GITHUB_DESTINATION: Development/output.log"

# Upload even when the compile or link fails, so the error is visible in GitHub.
REMOTE_SHA="$(gh api "$API_PATH" --jq '.sha')"
PAYLOAD="$STAGE_DIR/github-output-log.json"
python3 - "$LOG" "$REMOTE_SHA" "$PAYLOAD" <<'PY'
import base64
import json
import pathlib
import sys

log_path, sha, payload_path = sys.argv[1:4]
payload = {
    "message": "Stage29c native target compile and link result",
    "content": base64.b64encode(pathlib.Path(log_path).read_bytes()).decode("ascii"),
    "sha": sha,
}
pathlib.Path(payload_path).write_text(json.dumps(payload), encoding="utf-8")
PY

UPLOAD_RESPONSE="$(gh api --method PUT "$API_PATH" --input "$PAYLOAD")"
UPLOAD_COMMIT="$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"]["sha"])')"
echo "GITHUB_UPLOAD_STATUS: SUCCESS — Development/output.log updated (commit $UPLOAD_COMMIT)"

if [[ "$BUILD_RC" -ne 0 ]]; then
    exit "$BUILD_RC"
fi
if [[ "$VERIFY_RC" -ne 0 ]]; then
    exit "$VERIFY_RC"
fi
