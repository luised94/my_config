#!/bin/bash

# Set up network
dhcpcd

# Partition the disk
fdisk /dev/sda
# Create partition layout as desired, eg:
# - /dev/sda1 for boot partition (ext4, 500MB)
# - /dev/sda2 for swap partition (swap, 2GB)
# - /dev/sda3 for root partition (ext4, remaining space)
mkfs.ext4 /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3

# Mount the partitions
mount /dev/sda3 /mnt/gentoo
mkdir /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot

# Download stage3 tarball
cd /mnt/gentoo
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt
STAGE3_URL=$(cat latest-stage3-amd64.txt | grep -v "^#" | cut -d" " -f1)
wget $STAGE3_URL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Set up portage
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
echo "MAKEOPTS=\"-j$(nproc)\"" >> /mnt/gentoo/etc/portage/make.conf

# Configure system
cp -L /etc/resolv.conf /mnt/gentoo/etc/
  mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"

# Set up locale and timezone
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/env.d/02locale
env-update && source /etc/profile
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

# Set root password
passwd

# Install kernel sources and compile kernel
emerge sys-kernel/gentoo-sources
cd /usr/src/linux
make menuconfig
make && make modules_install
cp arch/x86_64/boot/bzImage /boot/kernel

# Configure fstab
echo "/dev/sda1 /boot ext4 defaults 0 2" >> /etc/fstab
echo "/dev/sda2 none swap sw 0 0" >> /etc/fstab
echo "/dev/sda3 / ext4 noatime 0 1" >> /etc/fstab

# Install bootloader
emerge sys-boot/grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Exit chroot
exit

# Unmount partitions and reboot
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
