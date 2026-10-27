# Restoring

The restore command brings back what the entries declare, from the
repository. It is named after the backup: for `name = "offsite"`, it is
`offsite-restore`. Run it as root.

- [Checking a backup](#checking-a-backup)
- [A restore, step by step](#a-restore-step-by-step)
- [Picking a snapshot](#picking-a-snapshot)
- [Over SSH](#over-ssh)
- [Undoing a restore](#undoing-a-restore)
- [When it stops](#when-it-stops)

## Checking a backup

Download an entry somewhere else, and change nothing:

```sh
sudo offsite-restore --target /tmp/restore-test vaultwarden
```

The files land under `/tmp/restore-test`, at their usual paths. `--help`
lists the entries.

## A restore, step by step

```sh
sudo offsite-restore              # every entry
sudo offsite-restore vaultwarden  # or the ones named
```

1. It lists the last 5 snapshots, says which one it restores, and waits for
   you to type `yes`.
2. It downloads the entries' paths into `<mountPoint>/.offsite-restore`.
   If one of them isn't in the snapshot, it stops there, and nothing has
   changed.
3. It stops the backup's timers and the entries' units.
4. It checks that no other program still has the data open, such as a
   desktop app. If one has, it starts the units again, names the program
   and stops: close it and run the command again.
5. For each path, it moves what is there into
   `<mountPoint>/.offsite-restore-old-<time>`, and the download into its
   place. Restored files get the owner of their folder, as a reinstalled
   host can give a service's user another ID.
6. It runs each entry's `restore` commands.
7. It starts the units and the backup's timer again.

The run is logged to `/var/log/offsite-restore.log`.

## Picking a snapshot

A reinstalled host's first backup holds its services' new, empty folders.
After that night, the newest snapshot is no longer the one to restore: the
list in step 1 gives it away by its size. Pick an older one by its ID:

```sh
sudo offsite-restore --snapshot 4f1c2a9e
```

## Over SSH

Restoring a VPN's state, like Tailscale's, can cut the SSH session you run
the command in. The restore carries on regardless: from step 2 on, it
ignores hangups and writes to the log as well as the terminal. Connect again
and read `/var/log/offsite-restore.log`.

## Undoing a restore

What a restore replaced stays in `<mountPoint>/.offsite-restore-old-<time>`,
at the same paths. To put a service's data back as it was:

```sh
sudo systemctl stop vaultwarden
old=$(ls -d /persist/.offsite-restore-old-* | tail -n 1)
sudo find /persist/vaultwarden -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo find "$old"/persist/vaultwarden -mindepth 1 -maxdepth 1 -exec mv -t /persist/vaultwarden {} +
sudo systemctl start vaultwarden
```

Delete the folder once everything works.

## When it stops

- **Before step 3**, nothing has changed.
- **In step 5 or 6**, it says so, which units it left stopped, and where the
  old data is. Fix the cause and run it again, or undo it as above.
