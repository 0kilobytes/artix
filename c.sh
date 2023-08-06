#!/bin/sh -e

# Boring stuff you should probably do
ln -sf /usr/share/zoneinfo/$region_city /etc/localtime
hwclock --systohc

# Localization
printf "en_US.UTF-8 UTF-8\n" >> /etc/locale.gen
locale-gen
printf "LANG=en_US.UTF-8\n" > /etc/locale.conf
printf "KEYMAP=us\n" > /etc/vconsole.conf

# Host stuff
printf "$my_hostname\n" > /etc/hostname
printf "hostname=\"$my_hostname\"\n" > /etc/conf.d/hostname
printf "\n127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$my_hostname.localdomain\t$my_hostname\n" > /etc/hosts

if [ -z "$username" ]; then
    :
else
     useradd -m $username
     yes $user_password | passwd $username
fi

# Install boot loader
root_part_uuid=$(blkid $root_part -o value -s UUID)

if [[ $encrypted == "y" ]]; then
    my_params="cryptdevice=UUID=$(echo $root_part_uuid):root root=\/dev\/mapper\/root"
    if [[ $my_fs == "ext4" ]]; then
        my_params="cryptdevice=UUID=$(echo $root_part_uuid):root root=\/dev\/MyVolGrp\/root"
    fi
elif [[ $my_fs == "ext4" ]]; then
    my_params="root=\/dev\/MyVolGrp\/root"
fi

sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT.*$/GRUB_CMDLINE_LINUX_DEFAULT=\"$my_params\"/g" /etc/default/grub
[[ $encrypted == "y" ]] && sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --recheck
grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Root user
yes $root_password | passwd

sed -i '/%wheel ALL=(ALL) ALL/s/^#//g' /etc/sudoers

# Other stuff you should do
if [[ $my_init == "openrc" ]]; then
    rc-update add connmand default
elif [[ $my_init == "dinit" ]]; then
    ln -s /etc/dinit.d/connmand /etc/dinit.d/boot.d/
elif [[ $my_init == "runit" ]]; then
    ln -s /etc/runit/sv/connmand /etc/runit/runsvdir/default
elif [[ $my_init == "s6" ]]; then
    touch /etc/s6/adminsv/default/contents.d/connmand
    s6-db-reload
fi

[[ $my_fs == "ext4" && $my_init == "openrc" ]] && rc-update add lvm boot

printf "\n$my_swap\t\tswap\t\tswap\t\tsw\t0 0\n" >> /etc/fstab

if [[ $encrypted == "y" && $my_fs == "btrfs" ]]; then
    swap_uuid=$(blkid $part2 -o value -s UUID)

    mkdir /root/.keyfiles
    chmod 0400 /root/.keyfiles
    dd if=/dev/urandom of=/root/.keyfiles/main bs=1024 count=4
    yes $cryptpass | cryptsetup luksAddKey $part2 /root/.keyfiles/main
    printf "dmcrypt_key_timeout=1\ndmcrypt_retries=5\n\ntarget='swap'\nsource=UUID='$swap_uuid'\nkey='/root/.keyfiles/main'\n#\n" > /etc/conf.d/dmcrypt

    [[ $my_init == "openrc" ]] && rc-update add dmcrypt boot
fi

# Configure mkinitcpio
if [[ $my_fs == "ext4" ]]; then
    if [[ $encrypted == "y" ]]; then
        sed -i 's/^HOOKS.*$/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
    else
        sed -i 's/^HOOKS.*$/HOOKS=(base udev autodetect keyboard keymap modconf block lvm2 filesystems fsck)/g' /etc/mkinitcpio.conf
    fi
elif [[ $my_fs == "btrfs" ]]; then
    sed -i 's/BINARIES=()/BINARIES=(\/usr\/bin\/btrfs)/g' /etc/mkinitcpio.conf
    if [[ $encrypted == "y" ]]; then
        sed -i 's/^HOOKS.*$/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf
    else
        sed -i 's/^HOOKS.*$/HOOKS=(base udev autodetect keyboard keymap modconf block filesystems fsck)/g' /etc/mkinitcpio.conf
    fi
fi

mkinitcpio -P
