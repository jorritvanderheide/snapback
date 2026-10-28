# Compatibility

snapback runs as root on other people's hosts, and their configurations,
monitoring and scripts depend on its options, units and commands. This page
says what a release may and may not change. Changes are listed in
[CHANGELOG.md](../CHANGELOG.md).

- [Versions](#versions)
- [Backups](#backups)
- [Options](#options)
- [Units](#units)
- [The restore command](#the-restore-command)
- [Files](#files)
- [Not covered](#not-covered)

## Versions

From 1.0, snapback's version is `MAJOR.MINOR.PATCH`, tagged without a `v`.
A minor or patch release breaks nothing below. A major release may, and the
changelog then says what changed and what to do.

Before 1.0, any release may break things, and the changelog says what to
change. Backups always restore.

Pin a release in your flake to upgrade when you choose:

```nix
inputs.snapback.url = "git+https://codeberg.org/BW20/snapback?ref=refs/tags/0.1.0";
```

## Backups

Every snapshot that a release wrote restores with every later release,
across major releases too. restic records each path under its usual name,
with nothing of snapback's in it, so plain `restic restore` reads them as
well.

## Options

Everything under `services.snapback`: the names, their types and their
defaults.

- **Renaming or removing** an option is breaking. A renamed option keeps
  working, with a warning (`lib.mkRenamedOptionModule`), until the next
  major release.
- **Changing a default** so that a setup behaves differently is breaking.
- **Adding** an option is not.

snapback sets `paths` and `exclude` of `services.restic.backups.<name>`,
and adds to the restic unit. Which of the restic module's own options it
sets is covered too.

## Units

For a backup named `<name>`:

- `<name>-backup-snapshot.service`
- `<name>-backup-retry.timer`
- `<name>-backup-report@success.service` and
  `<name>-backup-report@failure.service`, with `$1` set to the outcome and
  systemd's `$MONITOR_*` variables

Renaming one is breaking: alerts, `OnFailure=` and scripts name them. So is
changing when a report runs, or what it is told.

## The restore command

- Its name, `<name>-restore`.
- Its arguments: entry names, `other` for `paths`, `--target DIR`,
  `--snapshot ID` and `--help`.
- It asks before it changes anything, and reads `yes` from its standard
  input, so a script can answer it.
- It exits with 0 when it restored, and with another status when it didn't.

Removing or renaming an argument, or changing what it does, is breaking.
Adding one is not.

## Files

- **The snapshot:** `<dataset>@restic`. Tools that prune or hold snapshots
  may match it.
- **A restore** downloads into `<mountPoint>/.<name>-restore`, keeps what it
  replaced in `<mountPoint>/.<name>-restore-old-<time>`, and logs to
  `/var/log/<name>-restore.log`.

Moving one of these is breaking.

## Not covered

These can change in any release:

- What the restore command and the units print, and the units'
  descriptions.
- How often and how long a failed run is retried. The changelog says when
  it changes.
- Where the snapshot is mounted during a run.
- Anything in `module.nix` and `restore.sh` that isn't an option.
