{
  description = "restic backups that read a ZFS snapshot, with per-service entries and a restore command";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      nixosModules.default = ./module.nix;

      checks.x86_64-linux.default = pkgs.testers.runNixOSTest {
        imports = [ ./tests/vm.nix ];
        defaults.imports = [ self.nixosModules.default ];
      };

      formatter.x86_64-linux = pkgs.nixfmt-tree;
    };
}
