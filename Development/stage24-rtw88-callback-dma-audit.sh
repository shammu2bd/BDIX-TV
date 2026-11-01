#!/bin/bash
set -euo pipefail
REPO='shammu2bd/BDIX-TV'
NAME='RTL88WiFi-1.0.11-WCL-Sequoia-24H32-stage26-clean-source'
PROJECT=''
if [[ -n "${PROJECT_DIR:-}" && -f "$PROJECT_DIR/driver/RTL88WiFi/Makefile" ]]; then
 PROJECT="$(cd "$PROJECT_DIR" && pwd -P)"
elif [[ -f "$PWD/driver/RTL88WiFi/Makefile" ]]; then
 PROJECT="$(pwd -P)"
elif [[ -f "$HOME/Downloads/$NAME/driver/RTL88WiFi/Makefile" ]]; then
 PROJECT="$HOME/Downloads/$NAME"
fi
[[ -n "$PROJECT" ]] || { echo 'Cannot locate Stage26 project.'; exit 2; }
DRIVER="$PROJECT/driver/RTL88WiFi"
command -v gh >/dev/null 2>&1 || { echo 'GitHub CLI required.'; exit 2; }
gh auth status >/dev/null 2>&1 || { echo 'GitHub CLI authentication required.'; exit 2; }
STAGE="$PROJECT/build/stage24-rtw88-callback-dma-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STAGE"
REPORT="$STAGE/stage24-rtw88-callback-dma-audit.txt"

python3 - "$PROJECT" "$DRIVER" "$REPORT" <<'PY'
from pathlib import Path
import hashlib,re,sys
project,driver,out=map(Path,sys.argv[1:])
files=sorted(p for p in driver.rglob("*") if p.is_file() and p.suffix.lower() in {".cpp",".hpp",".h",".c",".cc"})
patterns=[
 ("OUTPUT_PACKET_WITH_COMPLETION",r"outputPacketWithCompletion|backendCompletion|CompletionCallback|completionCallback"),
 ("TX_SUBMIT_AND_COMPLETION",r"submitPacket|drainCompletions|claimCompleted|TicketPool::|complete\s*\(|finishTicket|transmitted"),
 ("DMA_ALLOC_FREE_MAP",r"allocCoherent|freeCoherent|dma_map|dma_unmap|map.*DMA|unmap.*DMA|prepare\s*\(|complete\s*\(|freeDMAList|releaseDMAEntries"),
 ("RADIO_STOP_AND_QUIESCE",r"RTW88IEEE80211::stop|\bstop\s*\(|synchronize|cancel_work|flush_work|disable.*interrupt|bus.master|BusMaster"),
 ("SKYWALK_QUEUE_HANDOFF",r"enqueuePackets|dequeuePackets|completePackets|requestDequeue|requestEnqueue|rxCompletionAction|txCompletionAction|rxSubmissionAction|txSubmissionAction"),
]
report=[
 "RTL88WiFi Stage24 — RTW88 callback, DMA and teardown contract audit",
 "PURPOSE: inspect code outside wcl24h32 adapters, especially the actual outputPacketWithCompletion implementation and RTW88 core callback/stop paths.",
 "SOURCE_CHANGES: NONE","BUILD: NOT RUN","INSTALL: NOT RUN","LOAD: NOT RUN",
 "OPENCORE_CHANGE: NONE","QUEUE_REGISTRATION: NOT CALLED","QUEUE_ENABLE: NOT CALLED",
 "RADIO_START: NOT RUN","KNOWN_GOOD_LEGACY_KEXT: NOT TOUCHED",""
]
report += ["=== DRIVER SOURCE INVENTORY / SHA-256 ===","SOURCE_FILE_COUNT: "+str(len(files))]
for p in files:
 report.append("SOURCE: {} SHA256={}".format(p.relative_to(project),hashlib.sha256(p.read_bytes()).hexdigest()))
for label,pattern in patterns:
 rx=re.compile(pattern,re.I)
 report += ["","=== "+label+" ==="]
 hits=0
 for p in files:
  lines=p.read_text(errors="replace").splitlines()
  found=[i for i,line in enumerate(lines) if rx.search(line) and not line.lstrip().startswith(("//","*"))]
  if not found: continue
  report.append("FILE: {} MATCHES: {}".format(p.relative_to(project),len(found)))
  for i in found:
   lo=max(0,i-14); hi=min(len(lines),i+15)
   report.append("CONTEXT: {}:{}-{}".format(p.relative_to(project),lo+1,hi))
   report.extend("  {:05d}: {}".format(n+1,lines[n]) for n in range(lo,hi))
   hits += 1
 report.append("TOTAL_MATCHES: "+str(hits))
report += [
 "","=== REQUIRED CONTRACT QUESTIONS ===",
 "1. Locate the exact implementation of outputPacketWithCompletion and prove mbuf ownership for every return path.",
 "2. Prove whether completion can occur synchronously before submit returns, asynchronously, more than once, or not at all on cancellation/reset/stop.",
 "3. Prove ticket publication ordering and prevent completion from racing ticket initialization or ticket reuse.",
 "4. Trace all RTW88 TX completion producers and every call into the supplied callback, including errors and teardown.",
 "5. Trace every coherent DMA allocation/free and descriptor prepare/complete pairing through device reset, failed start and stop.",
 "6. Prove RTW88 stop synchronizes all workqueues, NAPI-like workers, interrupt callbacks and DMA before backend bus-master disable and resource release.",
 "7. Match all Skywalk queue callback return-count semantics and packet ownership transfer to the Sequoia 24H32 ABI dossier.",
 "","STAGE24_STATUS: REVIEW_REQUIRED — search contexts require manual call-graph and branch analysis.",
 "ACTIVATION_GATE: BLOCKED — no queue registration/enable, packet handoff, BSD publication, radio start, build/install/load or OpenCore changes."
]
out.write_text("\n".join(report)+"\n",encoding="utf-8")
print("STAGE24_REPORT_PATH: "+str(out))
print("DRIVER_SOURCE_FILES: "+str(len(files)))
print("REPORT_BYTES: "+str(out.stat().st_size))
PY
[[ -s "$REPORT" ]] || { echo 'Stage24 report missing.'; exit 2; }
BYTES=$(wc -c < "$REPORT" | tr -d ' ')
(( BYTES <= 900000 )) || { echo "Report exceeds 900KB upload cap: $BYTES"; exit 2; }

upload_file() {
 local path="$1" api="$2" message="$3" payload="$4" response="$5"
 local oldsha
 oldsha="$(gh api "$api" --jq '.sha' 2>/dev/null || true)"
 python3 - "$path" "$oldsha" "$message" "$payload" <<'PY'
import base64,json,pathlib,sys
path,sha,message,payload=sys.argv[1:]
d={"message":message,"content":base64.b64encode(pathlib.Path(path).read_bytes()).decode()}
if sha:d["sha"]=sha
pathlib.Path(payload).write_text(json.dumps(d))
PY
 gh api --method PUT "$api" --input "$payload" > "$response"
 local put read
 put="$(python3 - "$response" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))["content"]["sha"])
PY
)"
 read="$(gh api "$api" --jq '.sha')"
 [[ "$put" == "$read" && -n "$put" ]] || { echo "Read-back SHA mismatch: $api"; return 1; }
 echo "$read"
}
SHA="$(upload_file "$REPORT" "repos/$REPO/contents/Development/stage24-rtw88-callback-dma-audit.txt" "Add Stage24 RTW88 callback and DMA audit" "$STAGE/report-payload.json" "$STAGE/report-response.json")"
echo "STAGE24_REPORT_UPLOAD: SUCCESS"
echo "GITHUB_REPORT: Development/stage24-rtw88-callback-dma-audit.txt"
echo "GITHUB_REPORT_BLOB_SHA: $SHA"
LOG="$PROJECT/output.log"
API="repos/$REPO/contents/Development/output.log"
gh api "$API" > "$STAGE/remote-log.json"
python3 - "$STAGE/remote-log.json" "$LOG" "$SHA" "$BYTES" <<'PY'
import base64,json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
old=base64.b64decode(d.get("content","")).decode("utf-8",errors="replace")
entry=("\n========== STAGE24 RTW88 CALLBACK / DMA AUDIT ==========\n"
 "STAGE24_REPORT: Development/stage24-rtw88-callback-dma-audit.txt\n"
 "STAGE24_REPORT_BLOB_SHA: "+sys.argv[3]+"\n"
 "STAGE24_REPORT_BYTES: "+sys.argv[4]+"\n"
 "STAGE24_STATUS: REVIEW_REQUIRED\nACTIVATION_GATE: BLOCKED\n"
 "SOURCE_CHANGES: NONE | BUILD: NOT RUN | INSTALL: NOT RUN | LOAD: NOT RUN | OPENCORE_CHANGE: NONE\n"
 "KNOWN_GOOD_LEGACY_KEXT: NOT TOUCHED\n")
pathlib.Path(sys.argv[2]).write_text(old+entry,encoding="utf-8")
PY
LOGSHA="$(upload_file "$LOG" "$API" "Record Stage24 RTW88 callback and DMA audit" "$STAGE/log-payload.json" "$STAGE/log-response.json")"
echo "CANONICAL_OUTPUT_LOG_UPLOAD: SUCCESS"
echo "CANONICAL_OUTPUT_LOG_BLOB_SHA: $LOGSHA"
echo "STAGE24_STATUS: REVIEW_REQUIRED"
echo "ACTIVATION_GATE: BLOCKED"
