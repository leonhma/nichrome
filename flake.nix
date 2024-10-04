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
          networking = { hostName = "nichrome"; };
        };
      };
    in flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        vmTools = pkgs.vmTools;
        basefs = nixos-generators.nixosGenerate {
          inherit system;
          format = "lxc";
          modules = [ nixosModule ];
        };
        meta = nixos-generators.nixosGenerate {
          inherit system;
          format = "lxc-metadata";
        };
      in {
        formatter = pkgs.nixfmt-classic;
        packages = {
          default = vmTools.runInLinuxVM (pkgs.stdenv.mkDerivation {
            name = "nichrome-${system}";
            preVM = vmTools.createEmptyImage {
              size = 16024;
              fullName = "nichrome-build";
            };
            memSize = 2048;
            dontUnpack = true;
            buildInputs = with pkgs; [ qemu util-linux e2fsprogs fuse-ext2];
            buildPhase = ''
              set -e
              echo "creating image"
              # Create the raw image
              qemu-img create -f raw disk.img 800M
              ls -la
              mkfs.ext4 disk.img
              mkdir rootfs
              ls -la
              df -h
              pwd
              echo "starting first unshare"
              mount -o loop disk.img ./rootfs/
              ls rootfs
              tar xJf ${basefs}/tarball/nixos-system-${system} -C rootfs
              echo "------"
              ls rootfs
              umount rootfs
              echo "unshare done"

              # Boot the VM
              qemu-system-x86_64 \
              -m 1024 \S
              -kernel ${pkgs.linux}/bzImage \
              -append "console=ttyS0 root=/dev/sda1 rw" \
              -nographic \
              -no-reboot \
              -drive file=./disk.img,format=raw,if=virtio
              
              mount -o loop disk.img rootfs

              ls rootfs
              touch rootfs/etc/gshadow
                  
              echo "------"
              ls rootfs

              # Export the modified rootfs
              ${pkgs.gnutar}/bin/tar -cJf nichrome-${system}-rootfs.tar.xz -C rootfs .

              umount rootfs
      
              rm -rf rootfs disk.img
            '';
            installPhase = ''
              mv nichrome-${system}.tar.xz $out
              mv ${meta}/tarball/nixos-system-${system}.tar.xz $out/nichrome-${system}-meta.tar.xz
            '';
          });
        };
      });
}
