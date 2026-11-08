# Security Policy

## Scope
TimeWarp runs with root privileges and writes raw data to block devices.
A wrong target disk means irreversible data loss. Treat any bug that could
cause writes to an unintended device as a security issue.

## Reporting a vulnerability
Please do not open a public issue. Use GitHub's
"Report a vulnerability" (Security tab -> Advisories) or contact the maintainer privately.
Include macOS version, script version, and steps to reproduce.

## Safe usage
- Read the script before running it with sudo.
- Verify source/target identifiers with `diskutil list` twice.
- Keep a second copy of critical data before cloning.
- Never commit recovery maps, disk images or logs: they may expose disk layout and file names.
