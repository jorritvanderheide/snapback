# Development

## Layout

```
flake.nix        the module and the checks
CHANGELOG.md     what changed in each release
SECURITY.md      what counts as a security problem, and where to report it
.forgejo/        CI, the release workflow and the issue templates
module.nix       the options, the units and the restore command
restore.sh       the restore command's logic, after the module's preamble
tests/vm.nix     the NixOS VM test
docs/            this, configuration, restoring, compatibility and architecture
```

## Checks

```sh
nix flake check   # the VM test
nix fmt           # nixfmt
```

CI runs `nix flake check` on every push to `main` and every pull request
(`.forgejo/workflows/ci.yml`), on the Forgejo runner on dapple (label
`nix`), which has KVM for the VM test.

Nix flakes only see files git tracks, so a new file needs `jj` or `git add`
to have seen it before `nix flake check` will.

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

Anything that could lose someone's data wants a test before it wants a
feature. A change to an option, a unit or the restore command goes in
`CHANGELOG.md`; see [Compatibility](compatibility.md) for what makes it
breaking.

## Releasing

1. In `CHANGELOG.md`, turn **Unreleased** into `## X.Y.Z`.
2. Push the commit to Codeberg, and a signed tag `X.Y.Z` for it, without a
   `v`:

   ```sh
   git tag -s X.Y.Z -m X.Y.Z main
   git push origin X.Y.Z
   ```

3. The tag starts `.forgejo/workflows/release.yml`, on the runner on dapple.
   It checks that the changelog has `## X.Y.Z`, runs `nix flake check`
   once more, and creates a **draft** Codeberg release with that part of the
   changelog as its notes.
4. Publish the draft. Releases before 1.0, and tags like `1.0.0-rc.1`, are
   marked as pre-releases.

There is nothing to build or upload: a flake pins the tag itself
(`?ref=refs/tags/X.Y.Z`). Before releasing anything that renames or
removes an option, a unit or an argument, see
[Compatibility](compatibility.md).
