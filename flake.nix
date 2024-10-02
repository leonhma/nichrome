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
            buildInputs = with pkgs; [ qemu util-linux e2fsprogs ];
            buildPhase = ''
              set -e

              # Create the raw image
              dd if=/dev/null of=disk.img bs=16M seek=256
              mkfs.ext4 disk.img

              # Populate the image rootfs
              mkdir rootfs
              ld=$(sudo losetup -f)
              sudo losetup $ld disk.img
              sudo mount $ld rootfs

              ls rootfs
              tar xJf ${basefs}/tarball/nixos-system-${system} -C rootfs
              echo "------"
              ls rootfs

              sudo umount $ld
              sudo losetup -d $ld
                
              # Boot the VM
              qemu-system-x86_64 \
              -m 1024 \S
              -kernel ${pkgs.linux}/bzImage \
              -append "console=ttyS0 root=/dev/sda1 rw" \
              -nographic \
              -no-reboot \
              -drive file=./disk.img,format=raw,if=virtio

              ld=$(losetup -f)
              sudo losetup $ld disk.img
              sudo mount $ld rootfs
    
              # Create /etc/gshadow if it doesn't exist
              touch rootfs/etc/gshadow
    
              # Export the modified rootfs
              ${pkgs.gnutar}/bin/tar -cJf nichrome-${system}.tar.xz -C rootfs .
    
              sudo umount $ld
              sudo losetup -d $ld

              rm -rf rootfs disk.img
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
