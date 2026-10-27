# Configuration

snapback adds to a restic backup that you configure yourself, under
`services.restic.backups.<name>`: its repository, password, timer and any
other restic option. snapback brings the snapshot, the entries and the
restore command, all under `services.snapback`.

- [The backup](#the-backup)
- [Entries](#entries)
- [Impermanence and preservation](#impermanence-and-preservation)
- [Append-only repositories](#append-only-repositories)
- [Reports](#reports)
- [Databases](#databases)
- [Every option](#every-option)

## The backup

```nix
{
  services.restic.backups.offsite = {
    environmentFile = "/run/secrets/restic-s3";
    initialize = true;
    passwordFile = "/run/secrets/restic-password";
    repository = "s3:https://s3.example.com/backups/host";

    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
  };

  services.snapback = {
    enable = true;
    mountPoint = "/persist";
    name = "offsite";
  };
}
```

`name` picks the backup, and names everything snapback adds: the units
start with `offsite-backup-`, and the restore command is `offsite-restore`.
Leave `paths` and `exclude` of the restic backup alone: snapback sets them
from the entries.

`dataset` defaults to the device of `mountPoint` in `fileSystems`. Set it
when the dataset is mounted some other way:

```nix
services.snapback.dataset = "zroot/persist";
```

## Entries

An entry is what one service needs back after a reinstall. Declare it in the
service's own module:

```nix
services.snapback.entries.jellyfin = {
  paths = [ "/persist/jellyfin" ];
  units = [ "jellyfin.service" ];

  # What Jellyfin rebuilds by itself.
  exclude = [
    "/persist/jellyfin/cache"
    "/persist/jellyfin/log"
  ];
};
```

- **`paths`** are backed up, and restored together.
- **`units`** are stopped while a restore replaces the paths, and started
  again after. List the timers that start the service too, so nothing writes
  halfway.
- **`exclude`** takes restic's exclude patterns.

Entries from several modules may share a name: their lists are merged.

Paths that belong to no service go in `paths`. A restore brings them back
as one more entry, `other`, without units:

```nix
services.snapback.paths = [ "/persist/home/alice/Documents" ];
```

## Impermanence and preservation

With impermanence or preservation, a path like `/var/lib/vaultwarden` is a
bind mount of a directory on the persistent dataset. Back it up by its usual
name, and tell snapback where its data lives:

```nix
{ lib, ... }:
{
  services.snapback = {
    mountPoint = "/persist";

    # /var/lib/vaultwarden lives in /persist/system/var/lib/vaultwarden.
    pathOnDataset =
      path: if lib.hasPrefix "/persist/" path then path else "/persist/system${path}";

    entries.vaultwarden = {
      paths = [ "/var/lib/vaultwarden" ];
      units = [ "vaultwarden.service" ];
    };
  };
}
```

restic then records `/var/lib/vaultwarden`, and a restore puts it back
through `/persist/system`, without crossing the bind mount.

## Append-only repositories

Give the host credentials that can't delete, and ransomware on it can't
wipe its backups: a bucket key without delete rights, or
`rest-server --append-only`. Then tell snapback:

```nix
services.snapback.appendOnly = true;
```

restic can't remove its own locks with such credentials, so the restore
command reads without one (`--no-lock`). A backup leaves its lock behind
for the same reason, and can't refresh it either: after 22.5 minutes,
restic gives up. The next try goes on where it stopped, so a long run
finishes in steps (see [Retries](architecture.md#retries)).

Prune and check from another machine, with credentials that can delete:

```sh
restic unlock
restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12
restic check
```

A first backup into a new repository may need more than 12 steps. Run it
once with credentials that can delete, through the usual unit, so it still
reads a snapshot:

```sh
sudo systemctl start restic-backups-offsite.service
```

## Reports

`report` runs after each backup, with `$1` set to `success` or `failure`:

```nix
{ pkgs, ... }:
{
  services.snapback.report = ''
    ${pkgs.curl}/bin/curl -fsS "https://hc-ping.com/<uuid>/$([[ $1 == success ]] && echo 0 || echo fail)"
  '';
}
```

systemd's `$MONITOR_SERVICE_RESULT`, `$MONITOR_EXIT_CODE` and
`$MONITOR_EXIT_STATUS` say how the run ended, for instance `exit-code` and
`3`. A run stopped by hand counts as a failure, and is retried.

Add programs to the report unit's `PATH` instead of writing their store
paths:

```nix
systemd.services."offsite-backup-report@".path = [ pkgs.curl ];
```

## Databases

A database's files are consistent in the snapshot, but some services keep
a dump to restore from instead. Back up the dump, and load it in `restore`:

```nix
{ pkgs, ... }:
{
  services.snapback.entries.immich = {
    paths = [ "/var/lib/immich" ];
    units = [ "immich-server.service" ];

    # Empties the database first, and loads the newest dump in one
    # transaction that stops at the first error.
    restore = ''
      dump=$(find /var/lib/immich/backups -name '*.sql.gz' | sort | tail -n 1)
      [[ -n $dump ]] || { echo "No database dump." >&2; return 1; }
      {
        echo 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'
        ${pkgs.gzip}/bin/gunzip --stdout "$dump"
      } |
        ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${pkgs.postgresql}/bin/psql --single-transaction --set ON_ERROR_STOP=on --dbname=immich
    '';
  };
}
```

The commands run as root, after the paths are back and with the units
still stopped. They run in a function: fail with `return 1`, not `exit 1`,
so the restore command can say which units it left stopped.

## Every option

| Option | Type | Default |
| --- | --- | --- |
| `enable` | boolean | `false` |
| `name` | string | |
| `mountPoint` | string | |
| `dataset` | string | `config.fileSystems.${mountPoint}.device` |
| `pathOnDataset` | function from path to path | `path: path` |
| `entries.<name>.paths` | list of strings | |
| `entries.<name>.units` | list of strings | `[ ]` |
| `entries.<name>.exclude` | list of strings | `[ ]` |
| `entries.<name>.restore` | lines | `""` |
| `paths` | list of strings | `[ ]` |
| `appendOnly` | boolean | `false` |
| `report` | null or lines | `null` |

The restic backup needs `createWrapper`, which is on by default: the restore
command runs `restic-<name>`.
