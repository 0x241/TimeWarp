# Contributing

1. Fork the repo and create a branch.
2. Keep the script POSIX-friendly where possible and compatible with macOS bash 3.2.
3. Run `shellcheck timewarp.sh` before opening a PR.
4. Test only on disposable disks or disk images (`hdiutil create`), never on real data.
5. Describe what you changed and how you tested it.

Any change touching `dd`, `ddrescue`, `diskutil erase*` or `resizeContainer`
must keep the confirmation prompts and the source != target check.
