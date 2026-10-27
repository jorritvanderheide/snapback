{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.snapback;
  inherit (cfg) name;
  backup = config.services.restic.backups.${name};

  paths = cfg.paths ++ lib.concatMap (entry: entry.paths) (lib.attrValues cfg.entries);

  # restic reads a snapshot of the dataset instead of the live files, so a
  # database written to mid-backup is copied as it was at one moment.
  # Each path is bind-mounted from the snapshot over itself, so restic
  # still sees (and records) the usual paths.
  snapshot = "${cfg.dataset}@restic";
  snapshotDir = "/run/${name}-backup-snapshot";
  inSnapshot = path: snapshotDir + lib.removePrefix cfg.mountPoint (cfg.pathOnDataset path);

  backupUnit = "restic-backups-${name}.service";
  backupTimer = "restic-backups-${name}.timer";
  retryTimer = "${name}-backup-retry.timer";
  report = outcome: lib.optional (cfg.report != null) "${name}-backup-report@${outcome}.service";

  # Paths outside the entries are restored as one more, without units.
  restoreEntries =
    cfg.entries
    // lib.optionalAttrs (cfg.paths != [ ]) {
      other = {
        inherit (cfg) paths;
        restore = "";
        units = [ ];
      };
    };
  quote = lib.escapeShellArg;
  # Always quoted, unlike escapeShellArg, so shellcheck doesn't read
  # restic=restic-offsite as arithmetic.
  literal = value: "'" + lib.replaceStrings [ "'" ] [ "'\\''" ] value + "'";
  restoreCommand = pkgs.writeShellApplication {
    name = "${name}-restore";

    runtimeInputs = with pkgs; [
      coreutils
      findutils
      lsof
      procps
      systemd
    ];

    text = ''
      command=${literal "${name}-restore"}
      restic=${literal "restic-${name}"}
      password_file=${literal (toString (backup.passwordFile or ""))}
      lock_args=(${lib.optionalString cfg.appendOnly "--no-lock"})
      staging=${literal "${cfg.mountPoint}/.${name}-restore"}
      old_prefix=${literal "${cfg.mountPoint}/.${name}-restore-old-"}
      log=${literal "/var/log/${name}-restore.log"}
      backup_timer=${literal backupTimer}
      timers=(${literal backupTimer} ${literal retryTimer})
      declare -A entry_paths=(${
        lib.concatMapAttrsStringSep " " (
          name: entry: "[${quote name}]=${quote (toString entry.paths)}"
        ) restoreEntries
      })
      declare -A entry_units=(${
        lib.concatMapAttrsStringSep " " (
          name: entry: "[${quote name}]=${quote (toString entry.units)}"
        ) restoreEntries
      })
      declare -A persisted=(${
        lib.concatMapStringsSep " " (path: "[${quote path}]=${quote (cfg.pathOnDataset path)}") paths
      })
      run_hook() {
        case $1 in
        ${lib.concatMapAttrsStringSep "\n" (name: entry: ''
          ${quote name})
          ${if entry.restore == "" then ":" else entry.restore}
          ;;
        '') restoreEntries}
        esac
      }
    ''
    + builtins.readFile ./restore.sh;
  };
in
{
  options.services.snapback = {
    enable = lib.mkEnableOption "restic backups that read a ZFS snapshot instead of the live files";

    name = lib.mkOption {
      type = lib.types.str;
      example = "offsite";
      description = ''
        The `services.restic.backups` entry to add to, which you configure
        yourself (repository, password, timer). The units this module adds
        are named after it: `<name>-backup-snapshot`, `<name>-backup-retry`
        and `<name>-backup-report@`, and so is the `<name>-restore` command.
      '';
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      example = "/persist";
      description = "Where the dataset that holds the backed-up paths is mounted.";
    };

    dataset = lib.mkOption {
      type = lib.types.str;
      default = config.fileSystems.${cfg.mountPoint}.device;
      defaultText = lib.literalExpression "config.fileSystems.\${config.services.snapback.mountPoint}.device";
      example = "zroot/persist";
      description = "The ZFS dataset to snapshot before each backup.";
    };

    pathOnDataset = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      default = path: path;
      defaultText = lib.literalExpression "path: path";
      example = lib.literalExpression ''
        path: if lib.hasPrefix "/persist/" path then path else "/persist/system''${path}"
      '';
      description = ''
        Where a backed-up path's data lives, below `mountPoint`. The default
        suits paths that are below it already. With impermanence or
        preservation, map a path like `/var/lib/foo` to the directory it is
        bind-mounted from.
      '';
    };

    entries = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            exclude = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "restic exclude patterns within those paths, for what the service rebuilds itself (caches, logs).";
            };

            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Paths the service needs back after a reinstall, as for `paths`.";
            };

            restore = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "Commands the restore command runs after putting the paths back, with the units still stopped. For data that is restored from a dump of it, like a database. They run in a function: fail with `return 1`, not `exit 1`, so the restore command says what it left stopped.";
            };

            units = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Units that use those paths, stopped while the restore command replaces them (timers too, so nothing writes halfway).";
            };
          };
        }
      );
      default = { };
      description = "What each service needs backed up, declared by the service's own module.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up besides the entries. The restore command restores them as one more entry, `other`, without units.";
    };

    appendOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the repository's credentials can't delete, as with
        `rest-server --append-only` or a bucket key without delete rights.
        restic then can't remove its locks, so the restore command reads
        without one (`--no-lock`). Prune and check the repository elsewhere,
        with credentials that can delete.
      '';
    };

    report = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      example = lib.literalExpression ''
        '''
          ''${pkgs.curl}/bin/curl -fsS "https://hc-ping.com/<uuid>/$([[ $1 == success ]] && echo 0 || echo fail)"
        '''
      '';
      description = ''
        Commands run after each backup, with `$1` set to `success` or
        `failure`, and systemd's `$MONITOR_SERVICE_RESULT`,
        `$MONITOR_EXIT_CODE` and `$MONITOR_EXIT_STATUS` describing the run.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = backup.createWrapper;
        message = "services.snapback needs services.restic.backups.${name}.createWrapper, for ${name}-restore.";
      }
    ];

    environment.systemPackages = [ restoreCommand ];

    services.restic.backups.${name} = {
      inherit paths;
      exclude = lib.concatMap (entry: entry.exclude) (lib.attrValues cfg.entries);
    };

    # Started by the backup's OnSuccess= (@success) and OnFailure=
    # (@failure). One instance per outcome: systemd only passes a unit how
    # its trigger ended ($MONITOR_*) when it has a single trigger, and the
    # backup listing one unit under both counts as two. A run stopped by
    # hand is a failure too (killed by TERM), and is retried.
    systemd.services."${name}-backup-report@" = lib.mkIf (cfg.report != null) {
      description = "Report how the ${name} backup ended: %i";
      scriptArgs = "%i";
      serviceConfig.Type = "oneshot";
      script = cfg.report;
    };

    # A unit of its own: every command of the backup's unit, even a "+"
    # one, starts with the mounts from the snapshot, so the snapshot has to
    # be mounted before that unit starts. Mounted by hand, not reached
    # through .zfs/snapshot: ZFS can't automount it while systemd sets up
    # the backup's mounts. Destroyed once the backup has stopped and no
    # longer needs it.
    systemd.services."${name}-backup-snapshot" = {
      description = "ZFS snapshot of ${cfg.mountPoint} for the ${name} backup";
      unitConfig.StopWhenUnneeded = true;

      path = [
        config.boot.zfs.package
        pkgs.util-linux
      ];

      preStop = ''
        umount ${snapshotDir}
        rmdir ${snapshotDir}
        zfs destroy ${snapshot}
      '';

      # The first two clean up after an interrupted run.
      script = ''
        umount ${snapshotDir} 2>/dev/null || true
        zfs destroy ${snapshot} 2>/dev/null || true
        zfs snapshot ${snapshot}
        mkdir -p ${snapshotDir}
        mount.zfs -o ro ${snapshot} ${snapshotDir}
      '';

      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
    };

    systemd.services."restic-backups-${name}" = {
      after = [ "${name}-backup-snapshot.service" ];
      requires = [ "${name}-backup-snapshot.service" ];
      serviceConfig.BindReadOnlyPaths = map (path: "${inSnapshot path}:${path}") paths;

      unitConfig = {
        OnFailure = [ retryTimer ] ++ report "failure";
        OnSuccess = report "success";
      };
    };

    # A failed run is tried again 5 minutes later, from this timer rather
    # than the unit's own Restart=: the unit stops in between, so the
    # snapshot goes too and each try takes a fresh one. A restart inside
    # the unit would keep its first snapshot, and fail for good on a new
    # service's path that isn't in it yet.
    #
    # With appendOnly credentials, restic can't refresh its lock (which
    # deletes the old one) and gives up after 22.5 minutes; `backup` has
    # no --no-lock. It saves its index every 10 minutes, so a retry goes
    # on where the last one stopped: a long run finishes in steps.
    systemd.timers."${name}-backup-retry" = {
      description = "Retry the failed ${name} backup";

      timerConfig = {
        OnActiveSec = "5min";
        Unit = backupUnit;

        # Inactive once it has fired, so the next failure can start it.
        RemainAfterElapse = false;
      };

      # At most 12 tries in 20 hours, enough for about 5 hours of steps, so
      # a failure that lasts, like expired credentials, doesn't retry and
      # report every 5 minutes until fixed.
      unitConfig = {
        StartLimitBurst = 12;
        StartLimitIntervalSec = "20h";
      };
    };
  };
}
