#!/usr/bin/env bash
# End-to-end migration test for timewarp.sh on VIRTUAL disks only (macOS).
# Usage: sudo -E tests/migration_test.sh [dd|rescue|smaller|partition|cancel]
#   dd        - healthy source, expects the dd path, exit code 0
#   rescue    - forces the ddrescue path (TIMEWARP_FORCE_RESCUE=1), exit code 0
#   smaller   - target smaller than source: refusal, disks untouched
#   partition - target given as a partition of the source disk: refusal
#   cancel    - user answers NO: exit code 130, disks untouched
# Refusals for the system disk are covered by tests/refusal_test.sh with stubs; this
# script never points TimeWarp at a real disk.
set -euo pipefail

MODE="${1:-dd}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SRC_DEV=""
DST_DEV=""

cleanup() {
  local d
  for d in "$SRC_DEV" "$DST_DEV"; do
    if [ -n "$d" ]; then
      hdiutil detach -force "$d" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

plist_get() {
  diskutil info -plist "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

attach_raw() {
  local img="$1" out i
  for i in 1 2 3; do
    if out="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$img" 2>/dev/null)"; then
      echo "$out" | awk 'NR==1 { print $1 }'
      return 0
    fi
    sleep 3
  done
  return 1
}

# Safety guard: refuse to continue unless the device is one of the images attached above
assert_virtual() {
  hdiutil info | grep -q "^$1" || fail "$1 is not an attached disk image - refusing to run"
}

manifest() {
  (cd "$1/data" && find . -type f | LC_ALL=C sort | xargs shasum -a 256)
}

DST_SIZE="1g"
if [ "$MODE" = "smaller" ]; then
  DST_SIZE="256m"
fi

mkfile -n 512m "$WORK/src.img"
mkfile -n "$DST_SIZE" "$WORK/dst.img"
SRC_DEV="$(attach_raw "$WORK/src.img")" || fail "cannot attach source image"
DST_DEV="$(attach_raw "$WORK/dst.img")" || fail "cannot attach target image"
assert_virtual "$SRC_DEV"
assert_virtual "$DST_DEV"
echo "--- diskutil view of the attached images (diagnostics) ---"
for d in "$SRC_DEV" "$DST_DEV"; do
  echo "$d: WholeDisk=$(plist_get "$d" WholeDisk) VirtualOrPhysical=$(plist_get "$d" VirtualOrPhysical) TotalSize=$(plist_get "$d" TotalSize) Stores=$(plist_get "$d" APFSPhysicalStores.0.APFSPhysicalStore)"
done
echo "source=$SRC_DEV target=$DST_DEV mode=$MODE"

# Fixture: APFS volume with random files and a checksum manifest
diskutil partitionDisk "$SRC_DEV" GPT APFS TMSRC 100% >/dev/null
SRC_MNT="/Volumes/TMSRC"
[ -d "$SRC_MNT" ] || fail "source volume not mounted"
mkdir -p "$SRC_MNT/data/sub"
for n in 1 2 3 4 5; do
  dd if=/dev/urandom of="$SRC_MNT/data/file$n.bin" bs=1m count=8 2>/dev/null
  dd if=/dev/urandom of="$SRC_MNT/data/sub/nested$n.bin" bs=1m count=2 2>/dev/null
done
sync
manifest "$SRC_MNT" > "$WORK/expected.sha"
diskutil unmountDisk "$SRC_DEV" >/dev/null

TARGET_BEFORE="$(shasum -a 256 "$WORK/dst.img" | awk '{print $1}')"
SOURCE_BEFORE="$(shasum -a 256 "$WORK/src.img" | awk '{print $1}')"

export TERM=xterm TIMEWARP_LANG=en TIMEWARP_SKIP_FDA=1
if [ "$MODE" = "rescue" ]; then
  export TIMEWARP_FORCE_RESCUE=1
fi

SRC_ARG="${SRC_DEV#/dev/}"
DST_ARG="${DST_DEV#/dev/}"
CONFIRM_ANSWER="YES"
case "$MODE" in
  partition) DST_ARG="${SRC_ARG}s2" ;;
  cancel) CONFIRM_ANSWER="NO" ;;
esac

set +e
printf '%s\n%s\n%s\n' "$SRC_ARG" "$DST_ARG" "$CONFIRM_ANSWER" \
  | "$ROOT/timewarp.sh" > "$WORK/run.log" 2>&1
RC=$?
set -e
echo "--- timewarp.sh exit code: $RC; log (blank lines removed) ---"
grep -v '^[[:space:]]*$' "$WORK/run.log" | tail -n 150

untouched() {
  [ "$TARGET_BEFORE" = "$(shasum -a 256 "$WORK/dst.img" | awk '{print $1}')" ] || fail "target was modified"
  [ "$SOURCE_BEFORE" = "$(shasum -a 256 "$WORK/src.img" | awk '{print $1}')" ] || fail "source was modified"
}

case "$MODE" in
  smaller)
    [ "$RC" -ne 0 ] || fail "script accepted a too-small target"
    grep -q "smaller than the source" "$WORK/run.log" || fail "missing size error message"
    untouched
    echo "PASS: smaller target rejected, disks untouched"
    exit 0
    ;;
  partition)
    [ "$RC" -ne 0 ] || fail "script accepted a partition as target"
    grep -q "not a whole physical disk" "$WORK/run.log" || fail "missing whole-disk error message"
    untouched
    echo "PASS: partition identifier rejected, disks untouched"
    exit 0
    ;;
  cancel)
    [ "$RC" -eq 130 ] || fail "cancel must exit with 130, got $RC"
    untouched
    echo "PASS: cancellation returns 130, disks untouched"
    exit 0
    ;;
esac

[ "$RC" -eq 0 ] || fail "timewarp.sh exited with $RC"
if [ "$MODE" = "rescue" ]; then
  grep -q "ddrescue read every block" "$WORK/run.log" || fail "ddrescue path was not used"
else
  grep -q "dd (64M" "$WORK/run.log" || fail "dd path was not used"
fi

# The clone shares UUIDs with the source, so detach the source first
hdiutil detach -force "$SRC_DEV" >/dev/null 2>&1 || true
SRC_DEV=""

PART="$(diskutil list "$DST_DEV" | grep Apple_APFS | awk '{print $NF}' | head -n 1)"
[ -n "$PART" ] || fail "no APFS partition on target"
CONT="$(diskutil apfs list | awk -v part="$PART" '
  /Container disk[0-9]+/ { c = $3 }
  /Physical Store/ && index($0, part) { print c; exit }')"
[ -n "$CONT" ] || fail "no APFS container on target"

SIZE="$(plist_get "/dev/$CONT" TotalSize)"
[ "$SIZE" -gt 900000000 ] || fail "container was not expanded (size=$SIZE)"

VOL="$(diskutil list "$CONT" | grep "APFS Volume" | awk '{print $NF}' | head -n 1)"
[ -n "$VOL" ] || fail "no APFS volume on target container"
diskutil mount "$VOL" >/dev/null
DST_MNT="$(plist_get "$VOL" MountPoint)"
[ -d "$DST_MNT/data" ] || fail "data directory missing on target"

manifest "$DST_MNT" > "$WORK/actual.sha"
diff "$WORK/expected.sha" "$WORK/actual.sha" || fail "checksums differ after migration"
echo "PASS: $MODE migration preserved all files and expanded the container to $SIZE bytes"
