{
  description =
    "Generate a LXD container image to use with termina in chromeOS.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils = { url = "github:numtide/flake-utils"; };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, nixos-generators, flake-utils }:
    let
      nixosModule = { config, lib, pkgs, ... }: {
        config = {
          system.stateVersion = "24.11";
          networking = { hostName = "nixos"; };
          system.activationScripts.crostiniSetup = ''
            # Create empty /etc/gshadow file
            touch /etc/gshadow

            # Create /home/leonhardmasche/.config/cros-garcon.conf
            mkdir -p /home/leonhardmasche/.config
            echo "DisableAutomaticCrosPackageUpdates=false\nDisableAutomaticSecurityUpdates=false" > /home/leonhardmasche/.config/cros-garcon.conf
          '';
        };
      };
    in flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        basefs = nixos-generators.nixosGenerate {
          inherit system;
          format = "lxc";
          modules = [ nixosModule ];
        };
      in {
        formatter = pkgs.nixfmt-classic;
        packages = {
          lxcImage = pkgs.vmTools.runInLinuxVM
            (pkgs.runCommand "nixos-crostini-rootfs" {
              memSize = 2048;
              diskSize = 4096;
            } ''
              ${
                nixos-generators.packages.${system}.nixos-generate
              } --format lxc --out-link $out/rootfs.tar.xz
            '');
          lxcMeta = nixos-generators.nixosGenerate {
            inherit system;
            format = "lxc-metadata";
          };
        };
      });
}
