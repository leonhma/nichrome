{
  description =
    "Generate a LXD container image to use with termina in chromeOS.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
          lxcImage = pkgs.stdenv.mkDerivation {
            name = "nichrome-${system}";
            dontUnpack = true;
            buildInputs = with pkgs; [ qemu libguestfs-with-appliance ];
            buildPhase = ''
              set -e

              # Create the raw image
              qemu-img create -f raw disk.img 2G

              # Prepare contents using guestfish
              guestfish --rw -a disk.img <<EOF
              run
              part-init /dev/sda mbr
              part-add /dev/sda p 1 2048 -1
              mkfs ext4 /dev/sda1
              mount /dev/sda1 /
              upload ${basefs}/tarball/nixos-system-${system}.tar.xz /basefs.tar.xz
              tar-in /basefs.tar.xz / compress:xz
              umount /
              EOF
                
              # Boot the VM
              qemu-system-x86_64 \
              -m 1024 \
              -kernel ${pkgs.linux}/bzImage \
              -append "console=ttyS0 root=/dev/sda1 rw" \
              -nographic \
              -no-reboot \
              -drive file=./disk.img,format=raw,if=virtio

              guestfish --ro -a disk.img <<EOF
              run
              mount /dev/sda1 /
              copy-out / booted
              EOF
    
              # Create /etc/gshadow if it doesn't exist
              touch booted/etc/gshadow
    
              # Export the modified rootfs
              ${pkgs.gnutar}/bin/tar -cJf nichrome-${system}.tar.xz -C booted .
    
              rm -rf mnt disk.img
            '';
            installPhase = ''
              mv nichrome-${system}.tar.xz $out
            '';
          };
          lxcMeta = nixos-generators.nixosGenerate {
            inherit system;
            format = "lxc-metadata";
          };
        };
      });
}
