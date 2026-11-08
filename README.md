# TimeWarp
### Resilient APFS Time Machine Drive Migration & Bad-Sector Recovery for macOS

```
   ┌──────────────────────┐                     ┌──────────────────────┐
   │  Failing APFS Drive  │                     │   New Target Drive   │
   │  [■■■■■■■■░░░■■■■■]  │  ─── TimeWarp ───►  │  [■■■■■■■■■■■■■■■■■] │
   │    1.4 TB / Bad I/O  │   dd / ddrescue     │     8 TB Expanded    │
   └──────────────────────┘                     └──────────────────────┘
```

**TimeWarp** is an interactive macOS CLI utility designed to solve a notoriously frustrating problem: migrating an encrypted or unencrypted APFS Time Machine backup drive to a larger destination disk, especially when the source disk is developing bad sectors and causes Finder, Disk Utility, and raw `dd` block-copies to abort mid-transfer.

> **Warning:** TimeWarp **erases the target disk completely**. Double-check both disk identifiers. Keep the source disk untouched until you have confirmed the new copy (see [Verify your backup history](#verify-your-backup-history)).

---

## The Problem

- Time Machine on APFS relies on tightly coupled APFS container snapshots. Traditional file copy (`cp`, `rsync`) destroys hard links, snapshot metadata, and encryption contexts.
- Simple block cloning (`dd`) instantly crashes with `Input/output error` as soon as the drive head hits a damaged cluster.
- When copying a smaller drive (e.g. 2 TB) to a larger drive (e.g. 8 TB), the partition table often reports corrupt container headers until manually rebuilt and resized.

TimeWarp automates permission auditing, health diagnostics, sector-safe copying, partition healing, APFS container expansion and post-copy verification in one guided pass.

---

## Features

- **Full Disk Access check**: reads a real sector from a raw device instead of guessing from the existence of a device node.
- **Smart transfer routing**:
  - **Healthy drive**: buffered raw block clone (`dd bs=64m`, with a progress indicator when your `dd` supports `status=progress`). Reads are sampled at five positions across the disk (start, 25%, 50%, 75%, end), not just the beginning.
  - **Failing drive**: fault-tolerant rescue with GNU `ddrescue` and a recovery map (skips damaged blocks without hanging).
  - **Automatic fallback**: if `dd` fails midway, TimeWarp switches to `ddrescue`.
- **Partition table repair and APFS expansion**: `diskutil repairDisk`, then `resizeContainer ... 0` to use 100% of the target. A failure of either is reflected in the final result.
- **Post-migration verification**: every APFS volume of the new container is checked with `diskutil verifyVolume`. Locked (encrypted) volumes are unlocked first; `diskutil` asks for the password itself, TimeWarp never sees it.
- **Multilingual interface**: English (default), Russian, Spanish, German, French, Portuguese and Chinese. Pick one at start-up or set `TIMEWARP_LANG`.

### Safety guards

TimeWarp is built to refuse rather than guess:

- Only **whole physical disks** (`disk2`) are accepted. Partitions (`disk2s2`) and virtual APFS containers are rejected.
- The **source must contain APFS**; this is checked before the target is touched.
- Neither disk may hold the **running system**. If TimeWarp cannot reliably determine which physical disks do, it stops.
- The **target must be at least as large** as the source.
- If a disk **cannot be unmounted**, nothing is written.
- Typing anything but `YES` at the confirmation cancels with exit code `130`.

### Recovery maps and resuming

Each source/target pair gets its own `ddrescue` map on your Desktop (`timewarp-<id>.map` plus a `.meta` file). If a map already exists you must type `RESUME` to continue or `NEW` to start over (the old map is archived). Before resuming, TimeWarp compares data that the map marks as already copied: extents up to 8 MiB are compared completely, larger ones at up to 32 evenly spread windows (always including the start and the end), for up to 8 extents. If anything differs, a read fails, or only zeros could be compared, resuming is refused. This is a **probabilistic** check: it makes reusing a map with a different drive of the same model unlikely, but only a full comparison or a trustworthy hardware identity would prove it. When in doubt, choose `NEW`.

---

## Requirements

- macOS 11 (Big Sur) or later. Older systems are untested; TimeWarp checks at run time whether `dd` supports `status=progress` and works without it.
- Target drive equal to or larger than the source drive.
- Full Disk Access granted to your terminal emulator:
  `System Settings → Privacy & Security → Full Disk Access → [Terminal / iTerm2]`
- *(Optional)* [Homebrew](https://brew.sh) for automatic `ddrescue` installation if bad sectors are detected. Homebrew cannot run as root, so TimeWarp installs it as the user who invoked `sudo`. If that fails, run `brew install ddrescue` yourself first.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/0x241/TimeWarp.git
cd TimeWarp

# Make script executable
chmod +x timewarp.sh

# Run with root privileges
sudo ./timewarp.sh

# Choose the language without the prompt (keep the variable with -E)
TIMEWARP_LANG=ru sudo -E ./timewarp.sh
```

---

## Interactive Workflow

```
[1/6] Checking Terminal permissions...
      ✓ Raw block device access confirmed.

[2/6] Connected storage devices:
      Source: /dev/disk1 (2 TB failing internal HDD)
      Target: /dev/disk5 (8 TB external USB drive)

[3/6] Checking /dev/disk1 for bad sectors...
      ⚠ I/O errors detected while reading the disk!
      → Using GNU ddrescue with a recovery map.

[4/6] Unmounting disks for safe cloning...
[5/6] Starting data transfer...
      ⚠ ddrescue could not recover 9216 bytes. Files stored in those areas may be damaged.

[6/6] Repairing the partition table and expanding the APFS container...
      ✓ APFS container expanded to the maximum size.
      ✓ All volumes passed verification.
```

### Result and exit codes

| Result | Meaning | Exit code |
|---|---|---|
| Success | Copied, expanded and verified | `0` |
| Warnings | Some data could not be recovered, or verification/repair reported problems. **Do not erase the source.** | `2` |
| Failed | The copy, the container expansion or the partition lookup failed. **Do not erase the source.** | `1` |
| Cancelled | You declined a confirmation | `130` |

---

## Verify your backup history

A passing `diskutil verifyVolume` checks the file-system structure; it does not prove that Time Machine can restore your history. Before you erase the old disk:

1. Add the new disk in **System Settings → General → Time Machine** and open **Browse Time Machine Backups**, or run `tmutil listbackups`.
2. Spot-check a few files from an old backup.
3. Keep the old disk until you are satisfied.

If `ddrescue` reported unrecovered bytes, files stored in those areas may be damaged even though the volume mounts.

---

## Post-Migration Tips

1. **Avoid UUID Collisions**: Disconnect the original drive to avoid APFS UUID conflicts. Do not erase it until you have verified the migrated backup history and successfully restored test files.
2. **Quota Management**: If you plan to share the new destination container between multiple Macs (e.g. iMac + MacBook), add a dedicated APFS volume inside Disk Utility with an explicit **Quota** to prevent one backup from starving the other.

---

## Testing

| Suite | Runs on | What it covers |
|---|---|---|
| `tests/unit_test.sh` | Linux, macOS | Disk-name validation, recovery-map parsing, the resume data check (identical data, other drive, unreadable devices, short reads, truncated target, a 1-byte difference inside a finished extent, differences in large sampled extents, all-zero data), `dd status=progress` detection, system-disk detection that fails closed, APFS detection, and completeness of all translations |
| `tests/refusal_test.sh` | Linux, macOS | Runs `timewarp.sh` against **stubbed** `diskutil`, `plutil`, `dd` and `ddrescue`. Proves it refuses (and makes no write call) for: system disk as target or source, undetectable system disk, partition instead of disk, virtual container, too-small target, non-APFS source, and a declined confirmation (`130`) |
| `tests/migration_test.sh` | macOS only | End-to-end clone between two **virtual** disks (disk images): `dd`, forced `ddrescue`, too-small target, partition identifier, cancel. Compares SHA-256 of every file and checks the container was expanded |

```bash
bash tests/unit_test.sh
bash tests/refusal_test.sh
sudo -E tests/migration_test.sh dd   # also: rescue, smaller, partition, cancel
```

The test hooks `TIMEWARP_SELFTEST`, `TIMEWARP_SKIP_FDA` and `TIMEWARP_FORCE_RESCUE` exist only for these tests. Do not set them for a real migration.

**What is not covered yet:** real bad sectors, and a genuine Time Machine history with snapshots, cannot be simulated in CI. Those are checked by hand before each release.

---

## Limitations

- Young project: the automated suites cover logic and virtual disks, not the full range of real hardware. Report issues with the full output.
- Only APFS Time Machine disks are supported (not HFS+).
- Non-English translations have not been reviewed by native speakers; corrections are welcome.

---

## License

MIT License. Feel free to use, modify, and distribute.
