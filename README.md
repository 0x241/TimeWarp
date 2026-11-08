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

---

## The Problem

- Time Machine on APFS relies on tightly coupled APFS container snapshots. Traditional file copy (`cp`, `rsync`) destroys hard links, snapshot metadata, and encryption contexts.
- Simple block cloning (`dd`) instantly crashes with `Input/output error` as soon as the drive head hits a damaged cluster.
- When copying a smaller drive (e.g. 2 TB) to a larger drive (e.g. 8 TB), the partition table often reports corrupt container headers until manually rebuilt and resized.

TimeWarp automates permission auditing, health diagnostics, sector-safe copying, partition healing, and APFS container expansion in one guided pass.

---

## Features

- **TCC / Full Disk Access Validation**: Checks whether Terminal has the raw device entitlements required to bypass sandbox permission errors before starting.
- **Smart Transfer Routing**:
  - **Healthy Drive**: High-speed, buffered raw block clone (`dd bs=64M`).
  - **Failing Drive**: Fault-tolerant rescue using GNU `ddrescue` with mapfile persistence (skips damaged blocks without hanging).
- **Partition Table Repair**: Reconstructs partition geometry on the destination disk post-clone via macOS `diskutil`.
- **Automatic APFS Container Expansion**: Instantly resizes the cloned APFS container to use 100% of the destination disk space (`resizeContainer ... 0`).
- **Destruction Guard**: Enforces strict confirmation checks and blocks identical source/target inputs.

---

## Requirements

- macOS 11 (Big Sur) or later.
- Target drive equal to or larger than the source drive.
- Full Disk Access granted to your terminal emulator:
  `System Settings → Privacy & Security → Full Disk Access → [Terminal / iTerm2]`
- *(Optional)* [Homebrew](https://brew.sh) for automatic `ddrescue` installation if bad sectors are detected.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/0x241/TimeWarp.git
cd timewarp

# Make script executable
chmod +x timewarp.sh

# Run with root privileges
sudo ./timewarp.sh
```

---

## Interactive Workflow

```
[1/6] Auditing TCC & Full Disk Access permissions...
      ✓ Raw disk access verified (/dev/rdisk*).

[2/6] Detecting connected storage media...
      Source: /dev/disk1 (2 TB failing internal HDD)
      Target: /dev/disk5 (8 TB external USB drive)

[3/6] Running sector read test & SMART audit...
      ⚠ I/O read failure detected on source disk.
      → Switching engine to GNU ddrescue.

[4/6] Unmounting active partitions...
[5/6] Transferring data blocks...
      [Progress: 1.7 TB recovered, 9 KB skipped bad blocks]

[6/6] Repairing GPT partition table & expanding APFS container...
      ✓ disk5s2 expanded from 2.0 TB to 8.0 TB.

Done. Your Time Machine history is intact and ready.
```

---

## Post-Migration Tips

1. **Avoid UUID Collisions**: If the old failing drive is still plugged in, wipe or disconnect it immediately so macOS doesn't get confused by duplicate APFS container UUIDs.
2. **Quota Management**: If you plan to share the new destination container between multiple Macs (e.g. iMac + MacBook), add a dedicated APFS volume inside Disk Utility with an explicit **Quota** to prevent one backup from starving the other.

---

## License

MIT License. Feel free to use, modify, and distribute.
