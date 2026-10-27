# Development

## Layout

```
flake.nix        the module and the checks
module.nix       the options, the units and the restore command
restore.sh       the restore command's logic, after the module's preamble
tests/vm.nix     the NixOS VM test
docs/            this, configuration, restoring and architecture
```

## Checks

```sh
nix flake check   # the VM test
nix fmt           # nixfmt
```

The VM test runs one machine with a ZFS pool on a second disk, an
append-only `rest-server`, and a service with an entry:

1. **A backup reads a snapshot.** The test changes the live file as soon as
   the snapshot is taken. The backup has to record the file as it was, at
   its usual path, and the snapshot has to be gone after.
2. **The restore command brings the data back.** The data is changed, then
   restored: it has to be as backed up, with the replaced data kept and the
   entry's `restore` commands run, and the service running again.
3. **A failed backup reports and is retried.** With the entry's directory
   gone, the run's bind mount has no source: `report` has to be told
   `failure`, and the retry timer has to run.

The first check is the one that guards the snapshot: without the bind
mounts, restic would read the live file, and it fails.

The restore command is built with `writeShellApplication`, so shellcheck
runs on it, preamble included, as part of the test.
