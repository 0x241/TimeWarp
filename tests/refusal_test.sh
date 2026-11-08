#!/usr/bin/env bash
# Safety-refusal tests for timewarp.sh. No real disks are involved: diskutil, plutil, dd,
# ddrescue and shasum are replaced by stubs, and every call that could write is recorded.
# Each refusal scenario must exit non-zero, print the expected message and make NO write
# call at all. Runs on Linux and macOS.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)" || { echo "FAIL - mktemp failed"; exit 1; }
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "FAIL - temporary directory was not created"
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"
MARK="$TMP/calls.log"
FAILS=0

cat > "$BIN/diskutil" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list)
    if [ "${2:-}" = "-plist" ]; then echo "LIST:$3"; fi
    exit 0 ;;
  info)
    if [ "${2:-}" = "-plist" ]; then echo "$3"; fi
    exit 0 ;;
  *)
    echo "diskutil $*" >> "$TW_MARK"
    exit 1 ;;
esac
STUB
cat > "$BIN/plutil" <<'STUB'
#!/usr/bin/env bash
read -r target
val="$(grep -F "$target|$2|" "$TW_FIXTURE" | head -n 1 | cut -d'|' -f3-)"
[ -n "$val" ] || exit 1
printf '%s\n' "$val"
STUB
cat > "$BIN/dd" <<'STUB'
#!/usr/bin/env bash
echo "dd $*" >> "$TW_MARK"
exit 0
STUB
cat > "$BIN/ddrescue" <<'STUB'
#!/usr/bin/env bash
echo "ddrescue $*" >> "$TW_MARK"
exit 1
STUB
chmod +x "$BIN"/*

base_fixture() {
  cat <<'EOF'
/dev/disk9|WholeDisk|true
/dev/disk9|VirtualOrPhysical|Physical
/dev/disk9|TotalSize|1000000000000
/dev/disk9|MediaName|SourceDrive
/dev/disk9|DiskUUID|AAAA-1111
LIST:/dev/disk9|AllDisksAndPartitions.0.Partitions.0.Content|EFI
LIST:/dev/disk9|AllDisksAndPartitions.0.Partitions.1.Content|Apple_APFS
/dev/disk5|WholeDisk|true
/dev/disk5|VirtualOrPhysical|Physical
/dev/disk5|TotalSize|2000000000000
/dev/disk5|MediaName|TargetDrive
/dev/disk0|WholeDisk|true
/dev/disk0|VirtualOrPhysical|Physical
/dev/disk0|TotalSize|2000000000000
LIST:/dev/disk0|AllDisksAndPartitions.0.Partitions.0.Content|Apple_APFS
/dev/disk6|WholeDisk|true
/dev/disk6|VirtualOrPhysical|Virtual
/dev/disk6|APFSPhysicalStores.0.APFSPhysicalStore|disk5s2
/dev/disk6|TotalSize|2000000000000
/|ParentWholeDisk|disk3
/System/Volumes/Data|ParentWholeDisk|disk3
disk3|APFSPhysicalStores.0.APFSPhysicalStore|disk0s2
disk3|VirtualOrPhysical|Virtual
EOF
}

# run NAME SRC DST ANSWER EXPECTED_RC EXPECTED_TEXT FIXTURE_EDIT(sed expr or empty)
run() {
  local name="$1" src="$2" dst="$3" answer="$4" want_rc="$5" want_text="$6" edit="$7" rc out
  base_fixture > "$TMP/fixture"
  if [ -n "$edit" ]; then
    sed -i.bak "$edit" "$TMP/fixture" && rm -f "$TMP/fixture.bak"
  fi
  : > "$MARK"
  out="$(printf '%s\n%s\n%s\n' "$src" "$dst" "$answer" \
    | PATH="$BIN:$PATH" TW_MARK="$MARK" TW_FIXTURE="$TMP/fixture" \
      TERM=xterm TIMEWARP_LANG=en TIMEWARP_SELFTEST=1 bash "$ROOT/timewarp.sh" 2>&1)"
  rc=$?
  local ok=1
  if [ "$rc" -ne "$want_rc" ]; then ok=0; echo "     exit code $rc, expected $want_rc"; fi
  if ! echo "$out" | grep -q "$want_text"; then ok=0; echo "     missing text: $want_text"; fi
  if [ "$want_rc" -ne 0 ] && grep -Eq "ddrescue|of=/dev/rdisk|^diskutil" "$MARK"; then
    # the happy-path control below is the only scenario allowed to reach unmount
    if [ "$name" != "control reaches unmount only" ]; then
      ok=0
      echo "     a write-capable command was called:"
      sed 's/^/       /' "$MARK"
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    echo "$out" | tail -n 8 | sed 's/^/       /'
    FAILS=$((FAILS + 1))
  fi
}

run "system disk as target is refused"       disk9 disk0 YES 1 "holds the running system" ""
run "system disk as source is refused"       disk0 disk5 YES 1 "holds the running system" ""
run "unknown system disk fails closed"       disk9 disk5 YES 1 "Could not reliably determine" '/^\/|ParentWholeDisk/d'
run "virtual disk without store fails closed" disk9 disk5 YES 1 "Could not reliably determine" '/^disk3|APFSPhysicalStores/d'
run "partition identifier is refused"        disk9 disk5s2 YES 1 "not a whole physical disk" ""
run "virtual APFS container is refused"      disk9 disk6 YES 1 "virtual APFS container" ""
run "too small target is refused"            disk9 disk5 YES 1 "smaller than the source" 's/^\/dev\/disk5|TotalSize|.*/\/dev\/disk5|TotalSize|500000000000/'
run "source without APFS is refused"         disk9 disk5 YES 1 "does not contain an APFS" '/Apple_APFS/d'
run "answering NO exits with 130"            disk9 disk5 NO 130 "cancelled" ""

# Control: with every check passing, the script goes on to unmount (the stub fails it),
# and must still not have called dd on a raw device or ddrescue.
# the source mimics a disk image, which diskutil reports as "Virtual" although it is a whole disk
run "control reaches unmount only"           disk9 disk5 YES 1 "Could not unmount" 's#^/dev/disk9|VirtualOrPhysical|Physical#/dev/disk9|VirtualOrPhysical|Virtual#'
if grep -Eq "ddrescue|of=/dev/rdisk" "$MARK"; then
  echo "FAIL - control scenario wrote to a device"
  FAILS=$((FAILS + 1))
elif ! grep -q "unmountDisk" "$MARK"; then
  echo "FAIL - control scenario never reached the unmount step"
  FAILS=$((FAILS + 1))
else
  echo "ok   - control scenario stopped at unmount before any write"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS scenario(s) failed"
  exit 1
fi
echo "all refusal tests passed"
