#!/usr/bin/env bash
# Unit tests for the pure logic of timewarp.sh. No disks needed; runs on Linux and macOS.
set -uo pipefail
if locale -a 2>/dev/null | grep -Eqi '^en_US\.utf-?8$'; then export LC_ALL=en_US.UTF-8; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/timewarp.sh"
FAILS=0

TMP="$(mktemp -d)" || { echo "FAIL - mktemp failed"; exit 1; }
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "FAIL - temporary directory was not created"
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT

extract() { sed -n "/^$1() {/,/^}/p" "$SCRIPT"; }
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$2', got '$3')"
    FAILS=$((FAILS + 1))
  fi
}

for fn in validate_disk map_unrecovered map_samples_match sample_read sample_equal extent_windows dd_supports_progress sys_disks has_apfs; do
  body="$(extract "$fn")"
  if [ -z "$body" ]; then
    echo "FAIL - function $fn not found in timewarp.sh"
    exit 1
  fi
  eval "$body"
done

# validate_disk
for v in disk2 /dev/disk10; do
  validate_disk "$v" && r=ok || r=bad
  check "validate_disk accepts $v" ok "$r"
done
for v in disk2s2 disk rdisk2 "" disk2x /dev/disk1s1; do
  validate_disk "$v" && r=ok || r=bad
  check "validate_disk rejects '$v'" bad "$r"
done

# map_unrecovered
printf '# Mapfile\n# Command line\n0x1000 ? 1\n0x0 0x1000 +\n0x1000 0x200 -\n0x1200 0x800 +\n0x1A00 0x100 ?\n' > "$TMP/a.map"
check "map_unrecovered counts bad and untried" 768 "$(map_unrecovered "$TMP/a.map")"
printf '# x\n0x0 + 1\n0x0 0x5000 +\n' > "$TMP/b.map"
check "map_unrecovered clean map" 0 "$(map_unrecovered "$TMP/b.map")"

# map_samples_match: identical data matches, a different "drive" does not
head -c 4194304 /dev/urandom > "$TMP/src.img"
cp "$TMP/src.img" "$TMP/same.img"
head -c 4194304 /dev/urandom > "$TMP/other.img"
printf '# Mapfile\n0x400000 + 1\n0x0 0x200000 +\n0x200000 0x200000 +\n' > "$TMP/full.map"
map_samples_match "$TMP/full.map" "$TMP/src.img" "$TMP/same.img" && r=match || r=differ
check "map_samples_match accepts the same data" match "$r"
map_samples_match "$TMP/full.map" "$TMP/src.img" "$TMP/other.img" && r=match || r=differ
check "map_samples_match rejects another disk with different data" differ "$r"
printf '# Mapfile\n0x0 ? 1\n0x0 0x400000 ?\n' > "$TMP/empty.map"
map_samples_match "$TMP/empty.map" "$TMP/src.img" "$TMP/other.img" && r=match || r=differ
check "map_samples_match with nothing finished is trivially fine" match "$r"

# Regression: unreadable devices must never be treated as "identical" (two empty reads)
map_samples_match "$TMP/full.map" "$TMP/missing1.img" "$TMP/missing2.img" && r=match || r=differ
check "map_samples_match rejects two unreadable devices" differ "$r"
map_samples_match "$TMP/full.map" "$TMP/src.img" "$TMP/missing2.img" && r=match || r=differ
check "map_samples_match rejects an unreadable target" differ "$r"
map_samples_match "$TMP/full.map" "$TMP/missing1.img" "$TMP/same.img" && r=match || r=differ
check "map_samples_match rejects an unreadable source" differ "$r"
head -c 1000 "$TMP/src.img" > "$TMP/short_src.img"
head -c 1000 "$TMP/src.img" > "$TMP/short_dst.img"
map_samples_match "$TMP/full.map" "$TMP/short_src.img" "$TMP/short_dst.img" && r=match || r=differ
check "map_samples_match rejects short reads even if both are equal" differ "$r"
head -c 2000000 "$TMP/src.img" > "$TMP/trunc_dst.img"
map_samples_match "$TMP/full.map" "$TMP/src.img" "$TMP/trunc_dst.img" && r=match || r=differ
check "map_samples_match rejects a truncated target" differ "$r"
printf '# Mapfile\n0x0 + 1\n0x0 0x100 +\n' > "$TMP/tiny.map"
map_samples_match "$TMP/tiny.map" "$TMP/src.img" "$TMP/same.img" && r=match || r=differ
check "map_samples_match fails closed when no extent can be sampled" differ "$r"

# Regression: a difference INSIDE a finished extent (first 64 KiB identical) must be found
head -c 8388608 /dev/urandom > "$TMP/big_src.img"
printf Y | dd of="$TMP/big_src.img" bs=1 seek=2097152 conv=notrunc 2>/dev/null
cp "$TMP/big_src.img" "$TMP/big_dst.img"
printf 'X' | dd of="$TMP/big_dst.img" bs=1 seek=2097152 conv=notrunc 2>/dev/null
printf '# Mapfile\n0x800000 + 1\n0x0 0x400000 +\n' > "$TMP/mid.map"
map_samples_match "$TMP/mid.map" "$TMP/big_src.img" "$TMP/big_dst.img" && r=match || r=differ
check "map_samples_match finds a 1-byte difference in the middle of a 4 MiB extent" differ "$r"
head -c 65536 "$TMP/big_src.img" > "$TMP/head.bin"
{ cat "$TMP/head.bin"; head -c 4194304 /dev/urandom; } > "$TMP/tail_a.img"
{ cat "$TMP/head.bin"; head -c 4194304 /dev/urandom; } > "$TMP/tail_b.img"
printf '# Mapfile\n0x800000 + 1\n0x0 0x400000 +\n' > "$TMP/head.map"
map_samples_match "$TMP/head.map" "$TMP/tail_a.img" "$TMP/tail_b.img" && r=match || r=differ
check "map_samples_match detects data that differs after an identical first 64 KiB" differ "$r"
map_samples_match "$TMP/mid.map" "$TMP/big_src.img" "$TMP/big_src.img" && r=match || r=differ
check "map_samples_match accepts an identical 4 MiB extent" match "$r"

# Large extents are sampled at start, middle and end (and more)
W="$(extent_windows 0 4294967296)"
check "extent_windows: 4 GiB extent is capped at 32 windows" 32 "$(echo "$W" | wc -l | tr -d ' ')"
check "extent_windows: first window is the extent start" "0 128" "$(echo "$W" | head -n 1)"
check "extent_windows: last window ends at the extent end" "$(( (4294967296 - 65536) / 512 )) 128" "$(echo "$W" | tail -n 1)"
W="$(extent_windows 0 268435456)"
check "extent_windows: 256 MiB extent gets 5 windows" 5 "$(echo "$W" | wc -l | tr -d ' ')"
check "extent_windows: small extent is compared completely" "8 2048" "$(extent_windows 4096 1048576)"

# Large (sparse) extent: difference at an interior sampled window, and all-zero data
SZ=314572800
dd if=/dev/zero of="$TMP/l_src.img" bs=1 count=0 seek=$SZ 2>/dev/null
W="$(extent_windows 0 $SZ)"
echo "$W" | while read -r sk sc; do
  head -c 65536 /dev/urandom | dd of="$TMP/l_src.img" bs=512 seek="$sk" conv=notrunc 2>/dev/null
done
MID="$(echo "$W" | sed -n "3p" | cut -d" " -f1)"
printf X | dd of="$TMP/l_src.img" bs=512 seek="$MID" conv=notrunc 2>/dev/null
cp "$TMP/l_src.img" "$TMP/l_same.img"
cp "$TMP/l_src.img" "$TMP/l_diff.img"
MID="$(echo "$W" | sed -n '3p' | cut -d' ' -f1)"
printf 'Y' | dd of="$TMP/l_diff.img" bs=512 seek="$MID" conv=notrunc 2>/dev/null
printf '# Mapfile\n0x12C00000 + 1\n0x0 0x12C00000 +\n' > "$TMP/l.map"
map_samples_match "$TMP/l.map" "$TMP/l_src.img" "$TMP/l_same.img" && r=match || r=differ
check "map_samples_match accepts identical data in a large extent" match "$r"
map_samples_match "$TMP/l.map" "$TMP/l_src.img" "$TMP/l_diff.img" && r=match || r=differ
check "map_samples_match finds a difference in the middle window of a large extent" differ "$r"
dd if=/dev/zero of="$TMP/z1.img" bs=1 count=0 seek=$SZ 2>/dev/null
cp "$TMP/z1.img" "$TMP/z2.img"
map_samples_match "$TMP/l.map" "$TMP/z1.img" "$TMP/z2.img" && r=match || r=differ
check "map_samples_match does not trust identical all-zero areas" differ "$r"

# dd_supports_progress: detects an unsupported option instead of failing the copy later
mkdir -p "$TMP/ddbad" "$TMP/ddok"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in status=*) exit 1 ;; esac; done\nexit 0\n' > "$TMP/ddbad/dd"
printf '#!/bin/sh\nexit 0\n' > "$TMP/ddok/dd"
chmod +x "$TMP/ddbad/dd" "$TMP/ddok/dd"
PATH="$TMP/ddbad:$PATH" dd_supports_progress && r=yes || r=no
check "dd_supports_progress is false when dd rejects status=progress" no "$r"
PATH="$TMP/ddok:$PATH" dd_supports_progress && r=yes || r=no
check "dd_supports_progress is true when dd accepts status=progress" yes "$r"

# sys_disks fail-closed behaviour with a stubbed plist_get
FIXTURE=""
plist_get() {
  case "$FIXTURE:$1:$2" in
    ok:/:ParentWholeDisk) echo disk3 ;;
    ok:/System/Volumes/Data:ParentWholeDisk) echo disk3 ;;
    ok:disk3:APFSPhysicalStores.0.APFSPhysicalStore) echo disk0s2 ;;
    ok:disk3:VirtualOrPhysical) echo Virtual ;;
    fusion:/:ParentWholeDisk) echo disk3 ;;
    fusion:disk3:APFSPhysicalStores.0.APFSPhysicalStore) echo disk0s2 ;;
    fusion:disk3:APFSPhysicalStores.1.APFSPhysicalStore) echo disk1s2 ;;
    nostore:/:ParentWholeDisk) echo disk3 ;;
    nostore:disk3:VirtualOrPhysical) echo Virtual ;;
    *) echo "" ;;
  esac
  return 0
}
FIXTURE=ok
check "sys_disks finds the physical store" "disk0 disk3" "$(sys_disks | sort -u | tr '\n' ' ' | sed 's/ $//')"
FIXTURE=fusion
check "sys_disks handles Fusion (two stores)" "disk0 disk1 disk3" "$(sys_disks | sort -u | tr '\n' ' ' | sed 's/ $//')"
FIXTURE=nostore
sys_disks >/dev/null && r=ok || r=refused
check "sys_disks refuses when a virtual disk has no physical store" refused "$r"
FIXTURE=empty
sys_disks >/dev/null && r=ok || r=refused
check "sys_disks refuses when nothing can be read" refused "$r"

# has_apfs with a stubbed plist_list
LISTFIX=""
plist_list() {
  case "$LISTFIX:$2" in
    apfs:AllDisksAndPartitions.0.Partitions.0.Content) echo EFI ;;
    apfs:AllDisksAndPartitions.0.Partitions.1.Content) echo Apple_APFS ;;
    hfs:AllDisksAndPartitions.0.Partitions.0.Content) echo EFI ;;
    hfs:AllDisksAndPartitions.0.Partitions.1.Content) echo Apple_HFS ;;
    *) echo "" ;;
  esac
  return 0
}
LISTFIX=apfs
has_apfs /dev/disk9 && r=yes || r=no
check "has_apfs finds an APFS partition" yes "$r"
LISTFIX=hfs
has_apfs /dev/disk9 && r=yes || r=no
check "has_apfs rejects HFS+ only" no "$r"
LISTFIX=none
has_apfs /dev/disk9 && r=yes || r=no
check "has_apfs fails closed when nothing is readable" no "$r"

# Every language must define every English key with the same number of %s placeholders
keys() { sed -n "/^msg_$1() {/,/^}/p" "$SCRIPT" | grep -oE '^ +[A-Z_0-9]+\)' | tr -d ' )'; }
line() { sed -n "/^msg_$1() {/,/^}/p" "$SCRIPT" | grep -E "^ +$2\)"; }
for lang in ru es de fr pt zh; do
  for k in $(keys en); do
    l="$(line "$lang" "$k")"
    if [ -z "$l" ]; then
      echo "FAIL - msg_$lang is missing $k"
      FAILS=$((FAILS + 1))
      continue
    fi
    a="$(line en "$k" | grep -o '%s' | wc -l | tr -d ' ')"
    b="$(echo "$l" | grep -o '%s' | wc -l | tr -d ' ')"
    if [ "$a" != "$b" ]; then
      echo "FAIL - $lang/$k placeholder count $b != $a"
      FAILS=$((FAILS + 1))
    fi
  done
done
echo "translation completeness checked"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS test(s) failed"
  exit 1
fi
echo "all unit tests passed"
