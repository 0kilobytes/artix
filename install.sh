#!/bin/sh -e

confirm_password () {
    local pass1="a"
    local pass2="b"
    until [[ $pass1 == $pass2 && $pass2 ]]; do
        printf "$1: " >&2 && read -rs pass1
        printf "\n" >&2
        printf "confirm $1: " >&2 && read -rs pass2
        printf "\n" >&2
    done
    echo $pass2
}

# Load keymap
sudo loadkeys us

# Check boot mode
[[ ! -d /sys/firmware/efi ]] && printf "Not booted in UEFI mode. Aborting..." && exit 1

# Choose my_init
until [[ $my_init == "openrc" || $my_init == "dinit" ]]; do
    printf "Init system (openrc/dinit): " && read my_init
    [[ ! $my_init ]] && my_init="openrc"
done

until [[ $my_kernel == "linux" || $my_kernel == "linux-zen" || $my_kernel == "linux-lts" ]]; do
    printf "kernel (linux/linux-zen/linux-lts " && read my_kernel
    [[ ! $my_kernel ]] && my_kernel="linux"
done

until [[ $network_tool == "connman" || $network_tool == "networkmanager" ]]; do
    printf "network tool (connman/networkmanager)" && read network_tool
    [[ ! $network_tool ]] && network_tool="connman"
done

# Wipe disk or not
printf "Wipe disk? (y/N): " && read wipe_disk
[[ ! $wipe_disk ]] && wipe_disk="n"

# Choose disk
while :
do
    sudo fdisk -l
    printf "\nDisk to install to (e.g. /dev/sda): " && read my_disk
    [[ -b $my_disk ]] && break
done

part1="$my_disk"1
part2="$my_disk"2
part3="$my_disk"3
if [[ $my_disk == *"nvme"* ]]; then
    part1="$my_disk"p1
    part2="$my_disk"p2
    part3="$my_disk"p3
fi

# Swap size
until [[ $swap_size =~ ^[0-9]+$ && (($swap_size -gt 0)) && (($swap_size -lt 97)) ]]; do
    printf "Size of swap partition in GiB (4): " && read swap_size
    [[ ! $swap_size ]] && swap_size=4
done

# Choose filesystem
until [[ $my_fs == "btrfs" || $my_fs == "ext4" ]]; do
    printf "Filesystem (btrfs/ext4): " && read my_fs
    [[ ! $my_fs ]] && my_fs="btrfs"
done

root_part=$part3
[[ $my_fs == "ext4" ]] && root_part=$part2

# Encrypt or not
printf "Encrypt? (y/N): " && read encrypted
[[ ! $encrypted ]] && encrypted="n"

my_root="/dev/mapper/root"
my_swap="/dev/mapper/swap"
if [[ $encrypted == "y" ]]; then
    cryptpass=$(confirm_password "encryption password")
else
    my_root=$part3
    my_swap=$part2
    [[ $my_fs == "ext4" ]] && my_root=$part2
fi
[[ $my_fs == "ext4" ]] && my_swap="/dev/MyVolGrp/swap"

# Timezone
until [[ -f /usr/share/zoneinfo/$region_city ]]; do
    printf "Region/City (e.g. 'America/Denver'): " && read region_city
    [[ ! $region_city ]] && region_city="America/Denver"
done

# Host
while :
do
    printf "Hostname: " && read my_hostname
    [[ $my_hostname ]] && break
done

# Users
root_password=$(confirm_password "root password")

installvars () {
    echo my_init=$my_init my_kernel=$my_kernel network_tool=$network_tool wipe_disk=$wipe_disk my_disk=$my_disk part1=$part1 part2=$part2 part3=$part3 \
        swap_size=$swap_size my_fs=$my_fs root_part=$root_part encrypted=$encrypted my_root=$my_root my_swap=$my_swap \
        region_city=$region_city my_hostname=$my_hostname \
        cryptpass=$cryptpass root_password=$root_password
}

printf "\nDone with configuration. Installing...\n\n"

# Install
sudo $(installvars) sh b.sh

# Chroot
sudo cp c.sh /mnt/root/ && \
    sudo $(installvars) artix-chroot /mnt /bin/bash -c 'sh /root/c.sh; rm /root/c.sh; exit' && \
    printf '\n`sudo artix-chroot /mnt /bin/bash` back into the system to make any final changes.\n\nYou may now poweroff.\n'
