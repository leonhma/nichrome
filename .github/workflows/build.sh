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
basefs=$(nixos-generate -f lxc -c config.nix)
sudo tar xJf $basefs -C rootfs
echo "------"
ls rootfs

sudo umount $ld
sudo losetup -d $ld

# Boot the VM
qemu-system-x86_64 \
  -m 1024 \
  -kernel arch/x86_64/boot/bzImage \
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
tar -cJf nichrome-x86.tar.xz -C rootfs .

sudo umount $ld
sudo losetup -d $ld
rm -rf rootfs disk.img