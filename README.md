# <img src="images/logo.svg" width="48" align="absmiddle" /> snapback

**Back up a ZFS snapshot with restic, and snap back from it with one command.**

A NixOS module for restic backups that read a snapshot of a ZFS dataset
instead of the live files. Each service declares what it needs backed up and
which units to stop, and one command brings it all back. See
[Getting started](#2-getting-started).

<br/>

![NixOS module](https://img.shields.io/badge/NixOS-module-5277c3?style=flat-square&logo=nixos&logoColor=white)
![restic and ZFS](https://img.shields.io/badge/built%20on-restic%20%2B%20ZFS-5277c3?style=flat-square)
[![License: EUPL-1.2](https://img.shields.io/badge/license-EUPL--1.2-blue?style=flat-square)](LICENSE)

A backup of live files is a backup of files changing under it. A database
written to while restic reads it comes out half old and half new, and you
find out when you restore it. And when you do restore, after a lost disk, it
is one service at a time, by hand: stop it, find its folders in the
snapshot, put them back, fix their owner, load its dump, start it again.

snapback takes a ZFS snapshot before each backup and mounts it over the
backed-up paths, so restic reads every file as it was at one moment and
still records its usual path. Each service's module says what to back up,
which units use it and how to load a dump, next to the rest of its
configuration. `offsite-restore` then brings back all of it, or the services
you name: it downloads first, stops the units, swaps the data in, runs the
dump loaders and starts the units again.

<br/>

## 1 Installation

Add the flake and import the module:

```nix
{
  inputs.snapback = {
    url = "git+https://codeberg.org/BW20/snapback";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # in your NixOS configuration:
  imports = [ inputs.snapback.nixosModules.default ];
}
```

The data to back up has to be on a ZFS dataset. With impermanence or
preservation, that is the dataset your persistent state lives on.

<br/>

## 2 Getting started

1. **Configure a restic backup** as usual: its repository, password and
   timer.

   ```nix
   services.restic.backups.offsite = {
     environmentFile = "/run/secrets/restic-s3";
     initialize = true;
     passwordFile = "/run/secrets/restic-password";
     repository = "s3:https://s3.example.com/backups/host";
   };
   ```

2. **Turn snapback on for it**, with the dataset's mount point:

   ```nix
   services.snapback = {
     enable = true;
     mountPoint = "/persist";
     name = "offsite";
   };
   ```

3. **Declare an entry for each service**, in its own module:

   ```nix
   services.snapback.entries.vaultwarden = {
     paths = [ "/persist/vaultwarden" ];
     units = [ "vaultwarden.service" ];
   };
   ```

4. **Check a backup** without changing anything:

   ```sh
   sudo offsite-restore --target /tmp/restore-test vaultwarden
   ```

5. **Restore** after a lost disk or a broken service:

   ```sh
   sudo offsite-restore              # everything
   sudo offsite-restore vaultwarden  # or only what you name
   ```

The command is named after the backup: `<name>-restore`.

<br/>

## 3 Safety and quality

A restore downloads everything before it touches anything, so a failed
download changes nothing. It keeps what it replaced, logs to a file and
carries on through a dropped SSH session. It refuses to start while a
program it doesn't know about still has the data open.

With `appendOnly`, the host's credentials can't delete: ransomware on the
host can add to its backups, but not wipe or overwrite them. snapback works
with that, from its retries to restores without a lock.

Every change is tested in a NixOS virtual machine: a backup to an
append-only `rest-server` that has to record the snapshot, not a file
changed after it; a restore; and a failed backup, which has to report and
run again. [Development](docs/development.md) has the details.

<br/>

## Table of contents

- [4 Documentation](#4-documentation)
- [5 Features](#5-features)
- [6 Options](#6-options)
- [7 Units and files](#7-units-and-files)
- [8 Questions or issues?](#8-questions-or-issues)
- [9 Support](#9-support)
- [10 License](#10-license)

<br/>

## 4 Documentation

- [**Configuration**](docs/configuration.md) - Entries, impermanence and
  preservation, append-only repositories, reports and databases.
- [**Restoring**](docs/restoring.md) - What the restore command does, step
  by step, and how to undo it.
- [**Architecture**](docs/architecture.md) - The units snapback adds, how a
  run uses the snapshot, and why it is built this way.
- [**Development**](docs/development.md) - The checks, the VM test and how
  the code is laid out.

<br/>

## 5 Features

### 5.1 One moment per backup

Before each run, snapback snapshots the dataset and mounts the snapshot over
each backed-up path, for that run only. restic sees the usual paths, so
snapshots and restores look the same as without snapback, and a database
comes out as it was at one moment. The snapshot is gone once the run ends.

### 5.2 Entries next to their service

An entry lists a service's paths, the units that use them, what to leave out
(caches, logs) and the commands that load a dump back. Each service's module
declares its own, so adding or removing a service changes one file.

### 5.3 One restore command

`<name>-restore` brings back every entry or the ones named, from the newest
snapshot or the one you pick. It gives restored files to whoever owns their
folder now, as a reinstall can hand out other user IDs. See
[Restoring](docs/restoring.md).

### 5.4 Retries on a fresh snapshot

A failed run is tried again 5 minutes later, up to 12 times in 20 hours,
each time on a new snapshot. restic keeps what earlier tries uploaded, so a
long first backup finishes in steps.

### 5.5 Reports

A shell snippet of your own runs after each backup, told whether it worked
and how it ended: a ping to healthchecks.io, a push to a status page, a
message. See [Reports](docs/configuration.md#reports).

<br/>

## 6 Options

All under `services.snapback`. [Configuration](docs/configuration.md)
explains each.

| Option | Default | What it does |
| --- | --- | --- |
| `enable` | `false` | Turn snapback on |
| `name` | | The `services.restic.backups` entry to add to, and the prefix of the units and the restore command |
| `mountPoint` | | Where the dataset with the backed-up paths is mounted |
| `dataset` | the device of `mountPoint` | The ZFS dataset to snapshot |
| `pathOnDataset` | `path: path` | Where a path's data lives below `mountPoint`, for bind-mounted state |
| `entries.<name>.paths` | | The service's paths |
| `entries.<name>.units` | `[ ]` | Units to stop during a restore |
| `entries.<name>.exclude` | `[ ]` | restic exclude patterns within the paths |
| `entries.<name>.restore` | `""` | Commands run after a restore, with the units still stopped |
| `paths` | `[ ]` | More paths, restored as the entry `other` |
| `appendOnly` | `false` | The credentials can't delete: restore without a lock |
| `report` | `null` | Commands run after each backup, with `success` or `failure` |

<br/>

## 7 Units and files

### 7.1 Units

For a backup named `offsite`:

- **`offsite-backup-snapshot.service`** takes the snapshot and mounts it,
  before each run, and removes both after.
- **`restic-backups-offsite.service`**, from NixOS's restic module, gets the
  bind mounts and starts the units below when it ends.
- **`offsite-backup-retry.timer`** starts a failed run again.
- **`offsite-backup-report@success.service`** and **`@failure`** run your
  `report` commands.

### 7.2 Files

- **The snapshot:** `<dataset>@restic`, mounted read-only on
  `/run/offsite-backup-snapshot` during a run.
- **A restore** downloads into `<mountPoint>/.offsite-restore`, keeps what
  it replaced in `<mountPoint>/.offsite-restore-old-<time>`, and logs to
  `/var/log/offsite-restore.log`.

### 7.3 Network

snapback connects to nothing itself. restic talks to your repository, and
your `report` commands to wherever you send them.

<br/>

## 8 Questions or issues?

If something doesn't work, or you have an idea, please
[open an issue](https://codeberg.org/BW20/snapback/issues/new/choose). The source
and the issues live on [Codeberg](https://codeberg.org/BW20/snapback).

<br/>

## 9 Support

snapback is free. If you find it useful, you can support its development on
Liberapay:

[![Donate](https://liberapay.com/assets/widgets/donate.svg)](https://liberapay.com/BW20)

<br/>

## 10 License

Copyright © 2026 Jorrit van der Heide. Licensed under the [EUPL-1.2](LICENSE).

The logo is based on the [Nix snowflake](https://github.com/NixOS/nixos-artwork/tree/master/logo)
by Simon Frankau and Tim Cuthbertson,
[CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/), changed so that one
lambda melts into a drop.
