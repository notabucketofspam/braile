#!/usr/bin/sh
set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <root_password> <user_password> [hostname] [username]"
    exit 1
fi

ROOT_PASS="$1"
USER_PASS="$2"
HOSTNAME="${3:-archbtw}"
USERNAME="${4:-opc}"

timedatectl set-ntp true
pacman -Sy --noconfirm archlinux-keyring

wipefs -a /dev/sda && printf "n\n\n\n+512M\nef00\nn\n\n\n\n8300\nw\ny\n" | gdisk /dev/sda

mkfs.fat -F32 /dev/sda1
mkfs.ext4 -F /dev/sda2
mount /dev/sda2 /mnt
mount --mkdir /dev/sda1 /mnt/boot 
pacstrap -K /mnt base linux linux-firmware sudo vim nano networkmanager openssh grub efibootmgr qemu-guest-agent tmux
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -c '
set -e
ROOT_PASS="$1"
USER_PASS="$2"
HOSTNAME="$3"
USERNAME="$4"

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
systemctl enable NetworkManager sshd qemu-guest-agent
useradd -m -G wheel -s /usr/bin/bash "$USERNAME"
printf "%s:%s\n" "root" "$ROOT_PASS" | chpasswd
printf "%s:%s\n" "$USERNAME" "$USER_PASS" | chpasswd
sed -i "s/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/" /etc/sudoers
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

cat << "EOF" > /etc/ssh/sshd_config.d/10-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
' _ "$ROOT_PASS" "$USER_PASS" "$HOSTNAME" "$USERNAME"

umount -R /mnt && poweroff
