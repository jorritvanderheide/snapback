# Changelog

What changed in each release of snapback, newest first. What counts as
breaking is in [Compatibility](docs/compatibility.md).

## 0.1.0

- The first release. `services.snapback` snapshots a ZFS dataset before
  each run of a `services.restic.backups` entry, and mounts the snapshot
  over the backed-up paths for that run. Services declare their paths,
  units, excludes and restore commands as `entries`.
- `<name>-restore` restores every entry or the ones named, from the newest
  snapshot or `--snapshot ID`, or only downloads with `--target DIR`.
- A failed run is tried again 5 minutes later, on a fresh snapshot, up to 12
  times in 20 hours. `appendOnly` restores without a lock, for credentials
  that can't delete.
- `report` runs commands after each backup, told whether it worked.
