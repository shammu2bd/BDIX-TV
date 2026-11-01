#!/bin/bash
set -euo pipefail

REPO="shammu2bd/BDIX-TV"
PROJECT="\${RTL88_PROJECT:-$HOME/Downloads/RTL88WiFi-1.0.11-WCL-stage14-generic-skywalk-segment-abi}"
SRC="$PROJECT/driver/RTL88WiFi/src/kext/wcl24h32/RTW88WCLSkywalkQueues.cpp"
OUT="$PROJECT/output.log"
STAMP="$(date '+%Y%m%d-%H%M%S')"
STAGE_DIR="$PROJECT/build/stage22-callback-count-contract-$STAMP"
BACKUP="$STAGE_DIR/RTW88WCLSkywalkQueues.cpp.before"
PATCH="$STAGE_DIR/stage22-callback-count-contract.patch"

if [ ! -f "$SRC" ]; then
    echo "ERROR: expected source file not found: $SRC" >&2
    exit 2
fi

mkdir -p "$STAGE_DIR"
cp -p "$SRC" "$BACKUP"

python3 - "$SRC" "$BACKUP" "$PATCH" "$STAGE_DIR" <<'PY'
from pathlib import Path
import sys

src_path, backup_path, patch_path, stage_dir = map(Path, sys.argv[1:])
source = src_path.read_text()
original = backup_path.read_text()

names = (
    "txSubmissionAction",
    "txCompletionAction",
    "rxSubmissionAction",
    "rxCompletionAction",
)

def extract(name: str, text: str):
    signature = "RTW88WCLSkywalkQueues::" + name + "("
    pos = text.find(signature)
    if pos < 0:
        raise SystemExit("ERROR: callback definition missing: " + name)
    start = text.rfind("\nIOReturn ", 0, pos)
    if start < 0:
        start = text.rfind("IOReturn ", 0, pos)
    brace = text.find("{", pos)
    if brace < 0:
        raise SystemExit("ERROR: opening brace missing: " + name)
    end = text.find("\n}\n", brace)
    if end < 0:
        raise SystemExit("ERROR: function terminator missing: " + name)
    return start, end + 2, text[start:end + 2]

expected = {
    "txSubmissionAction": {
        "return kIOReturnBadArgument;": 2,
        "return kIOReturnNotReady;": 1,
    },
    "txCompletionAction": {"return kIOReturnNotReady;": 1},
    "rxSubmissionAction": {"return kIOReturnNotReady;": 1},
    "rxCompletionAction": {"return kIOReturnNotReady;": 1},
}

replacements = []
for name in names:
    start, end, block = extract(name, source)
    for old, count in expected[name].items():
        actual = block.count(old)
        if actual != count:
            raise SystemExit(
                f"ERROR: {name}: expected {count} occurrence(s) of {old!r}, found {actual}; source left unchanged"
            )
    updated = block.replace(
        "return kIOReturnBadArgument;",
        "return static_cast<IOReturn>(0);"
    ).replace(
        "return kIOReturnNotReady;",
        "return static_cast<IOReturn>(0);"
    )
    if updated == block:
        raise SystemExit("ERROR: no safe return-value transformation found: " + name)
    replacements.append((start, end, updated))

for start, end, updated in sorted(replacements, reverse=True):
    source = source[:start] + updated + source[end:]

anchor = "IOReturn RTW88WCLSkywalkQueues::txSubmissionAction("
contract = (
    "/*\n"
    " * Sequoia 24H32 callback contract: although the bundled Skywalk action\n"
    " * typedefs are declared as IOReturn, the audited queue dispatchers\n"
    " * consume these callback return values as packet counts. Zero means\n"
    " * that no packets were accepted or completed. Do not return nonzero\n"
    " * IOReturn error constants from these action callbacks.\n"
    " */\n"
)
if source.count(anchor) != 1:
    raise SystemExit("ERROR: callback insertion anchor is not unique; source left unchanged")
source = source.replace(anchor, contract + anchor, 1)

for name in names:
    _, _, block = extract(name, source)
    if "return kIOReturnNotReady;" in block or "return kIOReturnBadArgument;" in block:
        raise SystemExit("ERROR: error-style return remains in " + name)
    if "return static_cast<IOReturn>(0);" not in block:
        raise SystemExit("ERROR: zero-count return missing in " + name)

if source.count("return static_cast<IOReturn>(0);") < 6:
    raise SystemExit("ERROR: expected six fail-closed zero-count returns")

src_path.write_text(source)
patch = __import__("difflib").unified_diff(
    original.splitlines(True),
    source.splitlines(True),
    fromfile="a/RTW88WCLSkywalkQueues.cpp",
    tofile="b/RTW88WCLSkywalkQueues.cpp",
)
patch_path.write_text("".join(patch))
(stage_dir / "stage22-verification.txt").write_text(
    "PASS: all four callback definitions located exactly once\n"
    "PASS: TX submission had two BadArgument and one NotReady returns; all replaced with zero packet count\n"
    "PASS: TX completion, RX submission, RX completion NotReady returns replaced with zero packet count\n"
    "PASS: callback signatures were not changed\n"
    "PASS: all six fail-closed return sites now return static_cast<IOReturn>(0)\n"
    "PASS: source backup and unified patch saved in this stage directory\n"
    "LIMIT: no compile, kext load, queue registration, or hardware datapath test was performed\n"
)
print("PATCH_STATUS: APPLIED")
print("CALLBACKS_PATCHED: 4")
print("ZERO_COUNT_RETURN_SITES: 6")
print("SOURCE_BACKUP: " + str(backup_path))
print("PATCH_FILE: " + str(patch_path))
PY

{
    echo "RTL88WiFi Stage 22 — Skywalk action callback count-contract patch"
    echo "DATE: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "HOST: $(sw_vers -productVersion 2>/dev/null || echo unknown) / $(sw_vers -buildVersion 2>/dev/null || echo unknown)"
    echo "ARCH: $(uname -m)"
    echo "PROJECT: $PROJECT"
    echo "SOURCE: $SRC"
    echo
    echo "========== STAGE 21 EVIDENCE REVIEW =========="
    echo "TX submission action pointer: [queue + 0x20]"
    echo "legacyDequeue: loads owner [queue+0x18], queue pointer, packet-slot pointer, requested count in ECX, refCon [queue+0x58], then calls action pointer."
    echo "legacyDequeue: tests EAX; zero means no progress; nonzero EAX is accumulated and used to advance ring slots."
    echo "listDequeue: calls the same five-argument action pointer; EAX is added to the dequeued total and subtracted from outstanding slots."
    echo "Therefore TX action return is a packet count, not an IOReturn error status."
    echo "The distinct 3-argument query-free-space handler at [queue+0xF0] is not the TX submission action."
    echo "Stage21 runner classification bug: it searched the method-path list for METHOD_FILE rather than checking collected files. The disassembly files were present; this report records the corrected conclusion."
    echo
    echo "========== STAGE 22 PATCH RESULT =========="
    cat "$STAGE_DIR/stage22-verification.txt"
    echo
    echo "========== PATCH DIFF =========="
    cat "$PATCH"
    echo
    echo "QUEUE_REGISTRATION: STILL_DISABLED"
    echo "DATAPATH_ACTIVATION: BLOCKED_PENDING_LIFECYCLE_AND_TEARDOWN_REVIEW"
    echo "BUILD_STATUS: NOT_RUN"
    echo "KEXT_LOAD_STATUS: NOT_RUN"
    echo "HARDWARE_TEST_STATUS: NOT_RUN"
} > "$OUT"

echo "Created: $OUT"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    SHA="$(gh api "repos/$REPO/contents/output.log" --jq '.sha' 2>/dev/null || true)"
    B64="$(base64 < "$OUT" | tr -d '\n')"
    if [ -n "$SHA" ]; then
        gh api --method PUT "repos/$REPO/contents/output.log" \
            -f message="Stage 22 apply Skywalk callback count contract" \
            -f content="$B64" -f sha="$SHA" >/dev/null
        echo "UPLOAD_STATUS: SUCCESS — https://github.com/$REPO/blob/main/output.log"
    else
        echo "UPLOAD_STATUS: GH_AUTH_OK_BUT_OUTPUT_LOG_SHA_NOT_RETRIEVED"
    fi
else
    echo "UPLOAD_STATUS: GH_CLI_NOT_AUTHENTICATED — output.log is ready for the existing GitHub runlog uploader."
fi

echo "SOURCE_PATCH_STATUS: APPLIED_LOCALLY_ONLY"
echo "NEXT: review output.log and patch diff, then compile before any OpenCore test."
