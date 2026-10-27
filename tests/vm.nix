{
  name = "snapback";

  nodes.machine =
    { pkgs, ... }:
    {
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "8425e349";
      virtualisation.emptyDiskImages = [ 1024 ];

      # Append-only, like a bucket key without delete rights.
      services.restic.server = {
        enable = true;
        appendOnly = true;
        extraFlags = [ "--no-auth" ];
        listenAddress = "8000";
      };

      services.restic.backups.test = {
        initialize = true;
        passwordFile = toString (pkgs.writeText "restic-password" "test");
        repository = "rest:http://127.0.0.1:8000/";
      };

      services.snapback = {
        enable = true;
        appendOnly = true;
        dataset = "tank/persist";
        mountPoint = "/persist";
        name = "test";
        report = ''echo "$1 $MONITOR_SERVICE_RESULT" >>/run/test-backup-reports'';

        entries.app = {
          paths = [ "/persist/app" ];
          restore = "echo ran >/persist/app/hook";
          units = [ "app.service" ];
        };
      };

      systemd.services.app.script = "sleep infinity";

      # Changes the live data once the snapshot is taken, which the backup
      # must not see.
      systemd.services.test-backup-snapshot.postStart = "if [ -d /persist/app ]; then echo after-snapshot >/persist/app/state; fi";
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed(
        "zpool create -O mountpoint=none tank /dev/vdb",
        "zfs create -o mountpoint=/persist tank/persist",
        "mkdir /persist/app",
        "echo v1 >/persist/app/state",
        "systemctl start app.service",
    )

    with subtest("A backup reads a snapshot and records the usual paths"):
      machine.succeed("systemctl start restic-backups-test.service")
      assert "/persist/app/state" in machine.succeed("restic-test ls latest")
      assert machine.succeed("restic-test dump latest /persist/app/state").strip() == "v1"
      assert machine.succeed("cat /persist/app/state").strip() == "after-snapshot"
      machine.wait_until_fails("zfs list -t snapshot tank/persist@restic")
      machine.succeed("grep -qx 'success success' /run/test-backup-reports")

    with subtest("The restore command brings the data back"):
      machine.succeed("echo v2 >/persist/app/state")
      machine.succeed("echo yes | test-restore app")
      assert machine.succeed("cat /persist/app/state").strip() == "v1"
      assert machine.succeed("cat /persist/.test-restore-old-*/persist/app/state").strip() == "v2"
      machine.succeed("test -f /persist/app/hook")
      machine.succeed("systemctl is-active app.service")

    with subtest("A failed backup reports and is retried"):
      # Fails at once: the run's bind mount from the snapshot has no source.
      machine.succeed("rm -r /persist/app")
      machine.fail("systemctl start restic-backups-test.service")
      machine.wait_until_succeeds("grep -q '^failure ' /run/test-backup-reports")
      machine.succeed("systemctl is-active test-backup-retry.timer")
  '';
}
