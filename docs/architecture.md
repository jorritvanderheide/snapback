# Architecture

snapback is one NixOS module, `module.nix`, and the restore command's
script, `restore.sh`. It adds a few systemd units around the restic backup
that NixOS's own module runs.

- [A run](#a-run)
- [The snapshot](#the-snapshot)
- [Retries](#retries)
- [Reports](#reports)
- [The restore command](#the-restore-command)

## A run

For `name = "offsite"`:

1. The restic timer starts `restic-backups-offsite.service`.
2. That unit requires `offsite-backup-snapshot.service`, which snapshots the
   dataset and mounts the snapshot read-only on
   `/run/offsite-backup-snapshot`.
3. The backup unit starts with each path bind-mounted from the snapshot
   over itself (`BindReadOnlyPaths`), in its own mount namespace. restic
   reads the snapshot, and records the usual paths.
4. When the run ends, the snapshot unit is no longer needed
   (`StopWhenUnneeded`): it unmounts the snapshot and destroys it.
5. `OnSuccess=` or `OnFailure=` starts the report, and on failure the retry
   timer.

## The snapshot

The snapshot is mounted by its own unit, not reached through
`.zfs/snapshot`. Every command of the backup unit, `ExecStartPre` and `+`
commands included, starts inside the bind mounts, so their source has to be
mounted before the unit starts. And ZFS can't automount a `.zfs/snapshot`
directory while systemd sets up those mounts.

It is always `<dataset>@restic`. The unit first removes one left over from
an interrupted run, so a crash or a reboot mid-backup doesn't block the next
one.

## Retries

A failed run starts `offsite-backup-retry.timer`, which starts the backup
again 5 minutes later. Not the unit's own `Restart=`: the unit stops in
between, so its snapshot goes, and each try takes a fresh one. A restart
inside the unit would keep the first snapshot, and fail for good on a path
added since.

The timer allows 12 tries in 20 hours, about 5 hours of steps, so a failure
that lasts, like expired credentials, doesn't retry every 5 minutes until
someone fixes it. 20 hours, so the count starts over before the next
night's run.

With append-only credentials, restic can't refresh its lock (it deletes the
old one) and gives up after 22.5 minutes. It saves its index every 10
minutes, so the next try goes on where that one stopped.

## Reports

`offsite-backup-report@.service` is a template, started as
`@success` from `OnSuccess=` and as `@failure` from `OnFailure=`. One unit
under both would get no `$MONITOR_*` variables: systemd only passes them to
a unit with a single trigger, and one unit listed in both counts as two.

A dependency that fails, such as the snapshot, fails the backup too, and
starts `@failure`.

## The restore command

`restore.sh` is the logic. `module.nix` puts a preamble in front of it with
everything that depends on the configuration, and builds it with
`writeShellApplication`, which runs shellcheck on the whole:

- `command`, `restic` (the `restic-<name>` wrapper), `password_file`,
  `lock_args`, `staging`, `old_prefix`, `log`, `backup_timer` and `timers`;
- `entry_paths` and `entry_units`, an array of each entry's paths and units;
- `persisted`, where each path's data lives on the dataset;
- `run_hook`, which runs an entry's `restore` commands.

The data is swapped through the dataset (`persisted`), not the paths
themselves: those may be bind mounts, and a move across mounts would copy
instead of rename.
