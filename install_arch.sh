#!/usr/bin/env bash
set -euo pipefail

read -rp "Target disk [/dev/sda]: " DISK
DISK="${DISK:-/dev/sda}"

read -rp "Hostname [jan]: " HOST
HOST="${HOST:-jan}"

read -rp "Username [jan]: " USERN
USERN="${USERN:-jan}"

read -srp "Password [1234]: " PASS
echo
PASS="${PASS:-1234}"

read -rp "Timezone [Europe/Warsaw]: " TZ
TZ="${TZ:-Europe/Warsaw}"

lsblk -d -o NAME,SIZE,MODEL
read -rp "Wipe and partition $DISK? Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

if [[ "$DISK" =~ (nvme|mmcblk|loop) ]]; then
  PART_PREFIX="${DISK}p"
else
  PART_PREFIX="$DISK"
fi

timedatectl set-ntp true
wipefs -af "$DISK"
parted -s "$DISK" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1GiB \
  set 1 esp on \
  mkpart root ext4 1GiB 100%

sleep 2

mkfs.fat -F32 "${PART_PREFIX}1"
mkfs.ext4 -F "${PART_PREFIX}2"

mount "${PART_PREFIX}2" /mnt
mount --mkdir "${PART_PREFIX}1" /mnt/boot

pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager sudo nano
genfstab -U /mnt > /mnt/etc/fstab

arch-chroot /mnt /bin/bash -s -- "$HOST" "$USERN" "$PASS" "$TZ" <<'EOF'
set -euo pipefail

CHROOT_HOST="$1"
CHROOT_USERN="$2"
CHROOT_PASS="$3"
CHROOT_TZ="$4"

ln -sf "/usr/share/zoneinfo/$CHROOT_TZ" /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$CHROOT_HOST" > /etc/hostname

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

useradd -m -G wheel "$CHROOT_USERN"
printf '%s:%s\n' "$CHROOT_USERN" "$CHROOT_PASS" | chpasswd
printf 'root:%s\n' "$CHROOT_PASS" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
EOF

umount -R /mnt
echo "Done. Remove the ISO and reboot."
