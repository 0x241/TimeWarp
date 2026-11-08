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

DST_SIZE="2g"
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
echo "--- source layout ---"
diskutil list "$SRC_DEV" || true
gpt -r show "$SRC_DEV" || true
SRC_PART="$(diskutil list "$SRC_DEV" | grep Apple_APFS | awk '{print $NF}' | head -n 1)"
SRC_STORE_SIZE="$(plist_get "/dev/$SRC_PART" TotalSize)"
case "$SRC_STORE_SIZE" in ''|*[!0-9]*) fail "could not read the source APFS store size" ;; esac
MIN_EXPANDED=$((SRC_STORE_SIZE + 300000000))
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
echo "--- warnings and errors reported by timewarp.sh ---"
grep -n -e '⚠' -e '\[Error\]' -e '\[Warning\]' -e 'Critical' "$WORK/run.log" || echo "(none)"

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

# Known limitation of disk-image targets: diskutil cannot repair their partition map
# (-69771: no EFI partition, backup GPT in the wrong place) and the resize then does not
# persist. TimeWarp must report both facts (exit code 2). Accept exactly that, nothing else.
REPAIR_LIMIT=0
if [ "$RC" -ne 0 ]; then
  OTHER_WARNINGS="$(grep -e '⚠' -e '\[Error\]' -e '\[Warning\]' -e 'Critical' "$WORK/run.log" | grep -v 'repairDisk' || true)"
  if [ "$RC" -eq 2 ] && [ -z "$OTHER_WARNINGS" ] && grep -q -e '-69771' "$WORK/run.log"; then
    REPAIR_LIMIT=1
    echo "NOTE: exit code 2 accepted - diskutil could not repair the image's partition map (-69771); no other warning was reported."
  else
    fail "timewarp.sh exited with $RC"
  fi
fi
if [ "$MODE" = "rescue" ]; then
  grep -q "ddrescue read every block" "$WORK/run.log" || fail "ddrescue path was not used"
else
  grep -q "dd (64M" "$WORK/run.log" || fail "dd path was not used"
fi

# The clone shares UUIDs with the source, so detach the source first
hdiutil detach -force "$SRC_DEV" >/dev/null 2>&1 || true
SRC_DEV=""

# Re-attach the target image, like plugging the new drive in again: judge what was
# persisted on "disk", not what the kernel had cached while TimeWarp was running.
hdiutil detach -force "$DST_DEV" >/dev/null 2>&1 || fail "cannot detach the target image"
DST_DEV=""
sleep 2
DST_DEV="$(attach_raw "$WORK/dst.img")" || fail "cannot re-attach the target image"
assert_virtual "$DST_DEV"
echo "--- after re-attaching the target: $DST_DEV ---"
diskutil list "$DST_DEV" || true
gpt -r show "$DST_DEV" || true
diskutil apfs list | grep -E "Container disk|Physical Store|Capacity Ceiling" || true

PART="$(diskutil list "$DST_DEV" | grep Apple_APFS | awk '{print $NF}' | head -n 1)"
[ -n "$PART" ] || fail "no APFS partition on target"
CONT="$(diskutil apfs list | awk -v part="$PART" '
  /Container disk[0-9]+/ { c = $3 }
  /Physical Store/ && index($0, part) { print c; exit }')"
[ -n "$CONT" ] || fail "no APFS container on target"

# Judge the expansion by the physical store that resizeContainer grows, and by the
# container's capacity ceiling; both must be clearly larger than the source's store.
SIZE="$(plist_get "/dev/$PART" TotalSize)"
CEILING="$(diskutil apfs list | awk -v c="$CONT" '
  /Container disk[0-9]+/ { cur = $3 }
  cur == c && /Capacity Ceiling/ { print $4; exit }')"
echo "--- expansion check: source store=$SRC_STORE_SIZE; target store $PART size=$SIZE; container $CONT ceiling=${CEILING:-unknown}; need > $MIN_EXPANDED ---"
case "$SIZE" in ''|*[!0-9]*) fail "could not read the size of $PART" ;; esac
EXPANSION_VERIFIED=1
if [ "$SIZE" -le "$MIN_EXPANDED" ]; then
  if [ "$REPAIR_LIMIT" -eq 1 ] && grep -q "did not grow" "$WORK/run.log"; then
    EXPANSION_VERIFIED=0
    echo "NOTE: the container did not grow, but TimeWarp reported exactly that (repairDisk failed on the image). Expansion cannot be verified on disk images here; it must be checked on a real drive."
  else
    fail "physical store was not expanded (size=$SIZE, source store=$SRC_STORE_SIZE)"
  fi
else
  case "$CEILING" in
    ''|*[!0-9]*) echo "NOTE: capacity ceiling could not be parsed; judged by the physical store size only" ;;
    *) [ "$CEILING" -gt "$MIN_EXPANDED" ] || fail "container capacity ceiling was not expanded (ceiling=$CEILING)" ;;
  esac
fi

VOL="$(diskutil list "$CONT" | grep "APFS Volume" | awk '{print $NF}' | head -n 1)"
[ -n "$VOL" ] || fail "no APFS volume on target container"
diskutil mount "$VOL" >/dev/null
DST_MNT="$(plist_get "$VOL" MountPoint)"
[ -d "$DST_MNT/data" ] || fail "data directory missing on target"

manifest "$DST_MNT" > "$WORK/actual.sha"
diff "$WORK/expected.sha" "$WORK/actual.sha" || fail "checksums differ after migration"
if [ "$EXPANSION_VERIFIED" -eq 1 ]; then
  echo "PASS: $MODE migration preserved all files and expanded the container to $SIZE bytes"
else
  echo "PASS (partial): $MODE migration preserved all files; expansion NOT verified (see NOTE above)"
fi
