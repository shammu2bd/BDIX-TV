#!/bin/bash
# Stage 35D — locate the real source checkout and Git metadata.
# Read-only: no Git initialization, source edits, builds, installs, kext loads, or OpenCore changes.
set -u
DOWNLOADS="$HOME/Downloads"
STAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '%s\n' '========== STAGE 35D: LOCATE PROJECT =========='
printf 'timestamp_utc=%s\nhost=%s\npwd=%s\nhome=%s\n' "$STAMP" "$(hostname 2>/dev/null || echo unknown)" "$PWD" "$HOME"
if [ ! -d "$DOWNLOADS" ]; then echo "ERROR: Downloads directory not found: $DOWNLOADS"; exit 2; fi

echo
echo '--- Candidate project directories ---'
find "$DOWNLOADS" -maxdepth 6 -type d \( -iname '*RTL88WiFi*' -o -iname '*RTW88*' -o -iname 'BDIX-TV' \) -print 2>/dev/null | sort

echo
echo '--- Git metadata (.git directories or files) ---'
find "$DOWNLOADS" -maxdepth 8 \( -type d -name .git -o -type f -name .git \) -print 2>/dev/null | sort

echo
echo '--- Expected native driver Makefile ---'
find "$DOWNLOADS" -maxdepth 9 -type f -path '*/driver/RTL88WiFi/Makefile' -print 2>/dev/null | sort

echo
echo '--- Any RTL88WiFi Makefiles (layout discovery) ---'
find "$DOWNLOADS" -maxdepth 9 -type f -iname 'Makefile' -path '*RTL88WiFi*' -print 2>/dev/null | sort | head -200

echo
echo '--- Nearby Development/src/build directories ---'
find "$DOWNLOADS" -maxdepth 6 -type d \( -name Development -o -name src -o -name build \) -print 2>/dev/null | sort | head -200

echo
echo '--- Git status for every discovered checkout ---'
while IFS= read -r gitdir; do
  [ -n "$gitdir" ] || continue
  candidate="${gitdir%/.git}"
  if [ -f "$gitdir" ]; then candidate="$(dirname "$gitdir")"; fi
  echo "GIT_CANDIDATE=$candidate"
  git -C "$candidate" rev-parse --show-toplevel 2>&1 || true
  git -C "$candidate" rev-parse --short HEAD 2>&1 || true
  git -C "$candidate" remote -v 2>&1 | head -4 || true
  echo
done < <(find "$DOWNLOADS" -maxdepth 8 \( -type d -name .git -o -type f -name .git \) -print 2>/dev/null)

echo 'READ_ONLY=YES'
echo 'SOURCE_OR_OPENCORE_MODIFIED=NO'
echo '========== END STAGE 35D =========='
