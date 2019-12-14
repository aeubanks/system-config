#!/bin/bash

# pacman -Sy unzip
# wget https://github.com/aeubanks/system-config/archive/master.zip
# unzip *.zip -d system-config
# system-config/install.sh

set -e

# cd to script dir
cd $(dirname $(readlink -f "$0"))

BOOT_PARTITION_NUM=1
LINUX_PARTITION_NUM=2
INSTALL_DEV='/dev/sda'
BOOT_PARTITION="$INSTALL_DEV$BOOT_PARTITION_NUM"
LINUX_PARTITION="$INSTALL_DEV$LINUX_PARTITION_NUM"
LVM_PHYSICAL_VOLUME_NAME='cryptlvm'
LVM_VOLUME_GROUP_NAME='vg_arthur'
LVM_LOGICAL_PARTITION_NAME='lp_arthur'

USERNAME='aeubanks'
HOSTNAME='aeubanks_desktop'
USER_SHELL='/usr/bin/fish'

LOCALE_GEN='en_US.UTF-8 UTF-8'
LOCALE_SET='en_US.UTF-8'

if [[ -z "$1" ]]
then # run in arch install iso

    # wait until online
    until ping -W2 -c1 'google.com' >/dev/null;
    do
        echo 'Waiting until online...'
        sleep 1
    done

    # sync time with network
    timedatectl set-ntp true

    echo 'Creating partitions...'
    # create partitions
    sgdisk -og "$INSTALL_DEV"
    sgdisk -n "$BOOT_PARTITION_NUM":2048:+512M -c "$BOOT_PARTITION_NUM":"EFI System Partition" -t "$BOOT_PARTITION_NUM":ef00 "$INSTALL_DEV"
    sgdisk -n "$LINUX_PARTITION_NUM":$(sgdisk -F "$INSTALL_DEV"):$(sgdisk -E "$INSTALL_DEV") -c "$LINUX_PARTITION_NUM":Linux -t "$LINUX_PARTITION_NUM":8e00 "$INSTALL_DEV"
    sgdisk -p "$INSTALL_DEV"

    cryptsetup luksFormat --type luks2 "$LINUX_PARTITION"
    cryptsetup open "$LINUX_PARTITION" "$LVM_PHYSICAL_VOLUME_NAME"

    vgcreate "$LVM_VOLUME_GROUP_NAME" /dev/mapper/"$LVM_PHYSICAL_VOLUME_NAME"
    lvcreate -l 100%FREE "$LVM_VOLUME_GROUP_NAME" -n "$LVM_LOGICAL_PARTITION_NAME"

    echo 'Creating filesystems...'
    # create file systems on partitions
    mkfs.fat -F 32 "$BOOT_PARTITION"
    mkfs.ext4 /dev/"$LVM_VOLUME_GROUP_NAME"/"$LVM_LOGICAL_PARTITION_NAME"

    echo 'Mounting partitions...'
    # mount partitions
    mount /dev/"$LVM_VOLUME_GROUP_NAME"/"$LVM_LOGICAL_PARTITION_NAME" /mnt/
    mkdir /mnt/boot/
    mount "$BOOT_PARTITION" /mnt/boot/

    echo 'pacstrapping...'
    # bootstrap pacman into Linux partition
    pacstrap /mnt/ \
    base \
    base-devel \
    lvm2 \
    tree \
    tmux \
    vim \
    git \
    clang \
    fish \
    noto-fonts noto-fonts-emoji ttf-inconsolata terminus-font adobe-source-han-sans-cn-fonts adobe-source-han-sans-jp-fonts adobe-source-han-sans-kr-fonts \
    powertop tlp \
    systemd-swap \
    reflector \
    pacman-contrib \
    openssh \
    networkmanager network-manager-applet \
    dex \
    xorg xorg-xinit xbindkeys \
    light \
    alsa-utils pulseaudio sox pasystray \
    i3-wm i3status dmenu \
    xsecurelock \
    feh nitrogen \
    rxvt-unicode \
    chromium \
    borg \
    libglvnd nvidia nvidia-settings

    echo 'Creating system config files...'
    sed -i 's/^# %wheel ALL=(ALL) ALL$/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers
    sed -i 's/^#HookDir/HookDir/' /mnt/etc/pacman.conf
    sed -i 's/^swapfc_enable=0$/swapfc_enabled=1/' /mnt/etc/systemd/swap.conf
    sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /mnt/etc/mkinitcpio.conf
    echo "$HOSTNAME" > /mnt/etc/hostname
    # boot configs
    mkdir -p /mnt/boot/loader/entries/
    cp loader.conf /mnt/boot/loader/
    cp arch.conf /mnt/boot/loader/entries/
    ROOT_UUID=$(blkid -s UUID -o value "$LINUX_PARTITION")
    sed -i 's/__UUID__/'"$ROOT_UUID"'/' /mnt/boot/loader/entries/arch.conf
    sed -i 's/__LVM_DEV__/'"$LVM_PHYSICAL_VOLUME_NAME"'/' /mnt/boot/loader/entries/arch.conf

    sed -i 's:__ROOT_DEV__:'"/dev/$LVM_VOLUME_GROUP_NAME/$LVM_LOGICAL_PARTITION_NAME"':' /mnt/boot/loader/entries/arch.conf

    echo 'Generating fstab...'
    # generate fstab config
    genfstab -U /mnt/ >> /mnt/etc/fstab

    cp install.sh /mnt/root/

    echo 'chrooting to Linux partition...'
    # chroot to Linux partition
    arch-chroot /mnt/ /root/install.sh chroot

elif [[ "$1" = 'chroot' ]]
then # run in chroot

    echo 'Setting time...'
    # set time
    ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
    hwclock --systohc

    echo 'Setting locale...'
    # generate and set locale
    echo "$LOCALE_GEN" > /etc/locale.gen
    locale-gen
    echo LANG="$LOCALE_SET" > /etc/locale.conf

    mkinitcpio -p linux

    echo 'Installing boot config...'
    # install boot config
    bootctl install

    echo 'Starting system services...'
    # start system services
    systemctl enable systemd-swap
    systemctl enable fstrim.timer

    # set root password
    echo 'Setting root password...'
    passwd

    # create user account
    echo "Setting password for $USERNAME..."
    useradd -m -G wheel -s "$USER_SHELL" "$USERNAME"
    passwd "$USERNAME"

    echo 'Please reboot now'

else # unknown command, print help

    echo "unknown command"
    echo "'$0' for script to run in arch install iso"
    echo "'$0 chroot' for script to run in chroot"

fi # [[ -n "$1" ]]

