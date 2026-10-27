# snapback

A NixOS module for restic backups that read a ZFS snapshot instead of the
live files. Each service declares what to back up and which units to stop,
and one command restores them.

Add it to a flake:

```nix
{
  inputs.snapback = {
    url = "git+https://codeberg.org/BW20/snapback";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, snapback, ... }:
    {
      nixosConfigurations.host = nixpkgs.lib.nixosSystem {
        modules = [
          snapback.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
```

Configure a restic backup as usual, and add the snapshot and the entries:

```nix
{
  services.restic.backups.offsite = {
    environmentFile = "/run/secrets/restic-s3";
    initialize = true;
    passwordFile = "/run/secrets/restic-password";
    repository = "s3:https://s3.example.com/backups/host";
  };

  services.snapback = {
    enable = true;
    mountPoint = "/persist";
    name = "offsite";

    entries.vaultwarden = {
      paths = [ "/persist/vaultwarden" ];
      units = [ "vaultwarden.service" ];
    };
  };
}
```

Before each run, the module snapshots the dataset mounted at `/persist` and
mounts the snapshot over the backed-up paths. restic records the usual
paths, with the data as it was at one moment, so a database written to
mid-backup is consistent.

## Restoring

Restore every entry, or the ones named:

```sh
sudo offsite-restore
sudo offsite-restore vaultwarden
```

The command downloads first, so a failed download changes nothing. Then it
stops the entries' units, swaps the data in, runs their `restore` commands
and starts the units again. It keeps the replaced data in
`/persist/.offsite-restore-old-<time>` and logs to
`/var/log/offsite-restore.log`.

- `--target DIR` downloads into `DIR` and changes nothing else.
- `--snapshot ID` restores that snapshot instead of the newest one.

The command takes its name from `name`: `<name>-restore`.

## Impermanence and preservation

With paths like `/var/lib/foo` bind-mounted from
`/persist/system/var/lib/foo`, map each path to where its data lives:

```nix
{ lib, ... }:
{
  services.snapback.pathOnDataset =
    path: if lib.hasPrefix "/persist/" path then path else "/persist/system${path}";
}
```

## Append-only repositories

Give the host credentials that can't delete, so ransomware on it can't wipe
its backups:

```nix
{
  services.snapback.appendOnly = true;
}
```

restic can't remove its locks with such credentials, so the restore command
reads without one. Prune and check from another machine, with credentials
that can delete:

```sh
restic unlock
restic forget --prune --keep-daily 7 --keep-weekly 5 --keep-monthly 12
restic check
```

## Failures

A failed backup runs again 5 minutes later, on a fresh snapshot, up to 12
times in 20 hours. restic saves its index every 10 minutes, so each try goes
on where the last one stopped.

## Reporting

Run commands after each backup, with `$1` set to `success` or `failure`:

```nix
{ pkgs, ... }:
{
  services.snapback.report = ''
    ${pkgs.curl}/bin/curl -fsS "https://hc-ping.com/<uuid>/$([[ $1 == success ]] && echo 0 || echo fail)"
  '';
}
```

systemd's `$MONITOR_SERVICE_RESULT`, `$MONITOR_EXIT_CODE` and
`$MONITOR_EXIT_STATUS` describe the run.

## Databases

Back up a dump, and load it back after a restore:

```nix
{
  services.snapback.entries.app = {
    paths = [ "/persist/app" ];
    units = [ "app.service" ];

    restore = ''
      psql -d app -f /persist/app/dump.sql || return 1
    '';
  };
}
```

The `restore` commands run with the units still stopped. Fail with
`return 1`, so the command reports what it left stopped.

## Tests

```sh
nix flake check
```

The VM test backs up a service's data from a snapshot to an append-only
`rest-server`, restores it, and checks that a failed backup reports and
runs again.

## License

[MIT](LICENSE)
