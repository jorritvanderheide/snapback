# Security policy

## Supported versions

Security fixes go into the latest release of snapback, and into `main`.
Older releases don't get separate fixes, so please update before you
report.

## Reporting a problem

Please don't open a public issue for a security problem. Codeberg, where the
issues are, has no private reports, so report it privately through the GitHub
mirror instead:

https://github.com/jorritvanderheide/snapback/security/advisories/new

Include the snapback release or commit
(`nix flake metadata --json | jq -r .locks.nodes.snapback.locked.rev`), the
NixOS version (`nixos-version`), your `services.snapback` configuration, the
kind of repository, and the steps to reproduce it. Leave out passwords,
credentials and repository URLs with credentials in them. Reports are looked
at before anything about them is made public.

## What counts

snapback runs as root. Before each backup it snapshots one ZFS dataset,
mounts the snapshot read-only, and gives the backup unit the entries' paths
from it. The restore command, run by root, writes only to the entries'
paths, to `<mountPoint>/.<name>-restore` and
`<mountPoint>/.<name>-restore-old-<time>`, and to its log; see
[Units and files](README.md#7-units-and-files).

So these are security problems:

- A backup that records data outside the entries' paths and `paths`.
- Data that a user can read through the snapshot's mount, the restore's
  folders or its log, but not on the live system.
- A restore that writes outside the places above, for instance through a
  symlink in the restored data or in a folder it moves things into.
- The repository's password or credentials ending up where other users can
  read them: a log, a process's arguments, a world-readable file.
- A user without root who can make snapback run commands, or change what it
  backs up or restores.

These are not, on their own:

- Anything that needs root to begin with.
- Commands you wrote yourself in `report` or an entry's `restore`.
- Credentials that can delete the repository's data. That is configuration:
  see [Append-only repositories](docs/configuration.md#append-only-repositories).
- How restic encrypts and stores the backups. Report those to
  [restic itself](https://github.com/restic/restic).

A bug that loses or damages data in a backup or a restore is serious too,
but it isn't secret: please report that as a normal issue, so others can see
it.
