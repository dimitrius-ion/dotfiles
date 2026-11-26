#!/usr/bin/env bash
# Install a minimal Arch Linux NEXT TO an existing install on the same LUKS2 + btrfs disk.
#
# Run from the Arch ISO, as root:
#   curl -fsSLO https://raw.githubusercontent.com/dimitrius-ion/dotfiles/main/install-arch.sh
#   bash install-arch.sh
#
# What it does: unlocks the existing encrypted partition, adds new @arch* subvolumes,
# installs a base system into them, builds unified kernel images (UKIs) on the shared
# EFI partition and adds firmware boot entries for them.
#
# What it never does: partition, format, luksFormat, or delete anything. The existing
# system's subvolumes (@, @home, ...) are only read (listed), never mounted for writing.
#
# Safe to re-run: if @arch already exists (an earlier run failed halfway), it offers to
# resume with the existing subvolumes instead of creating new ones.

set -euo pipefail

DISK=/dev/nvme0n1
ESP=${DISK}p1
LUKS=${DISK}p2
MAPPER=root
SUBVOLS=(@arch @arch-home @arch-log @arch-pkg @arch-snapshots)
PACKAGES=(base linux linux-lts linux-firmware amd-ucode btrfs-progs efibootmgr
          networkmanager iwd sudo fish git openssh terminus-font neovim)
MOUNT_OPTS=noatime,compress=zstd:3

# --- helpers ---------------------------------------------------------------------------
bold=$'\e[1m'; blue=$'\e[34m'; green=$'\e[32m'; red=$'\e[31m'; reset=$'\e[0m'
step()  { printf '\n%s%s== %s ==%s\n%s\n' "$bold" "$blue" "$1" "$reset" "$2"; }
ok()    { printf '%s  ✓ %s%s\n' "$green" "$1" "$reset"; }
die()   { printf '%s  ✗ %s%s\n' "$red" "$1" "$reset" >&2; exit 1; }
pause() { read -rp "  Press Enter to continue (Ctrl+C to stop) " _; }
ask()   { local v; read -rp "  $1: " v; [ -n "$v" ] || die "$1 can't be empty"; printf '%s' "$v"; }

# --- 0. pre-flight ---------------------------------------------------------------------
step "0. Pre-flight checks" \
"Checks that this is the Arch ISO booted in UEFI mode, that the disk layout is the one
this script expects (EFI partition + LUKS partition), and nothing else."
[ "$(id -u)" = 0 ] || die "run as root (the Arch ISO logs you in as root)"
[ -d /sys/firmware/efi ] || die "not booted in UEFI mode; reboot and pick the UEFI entry for the USB stick in F12"
[ -b "$ESP" ] && [ "$(blkid -s TYPE -o value "$ESP")" = vfat ] || die "$ESP is not the FAT EFI partition"
[ "$(blkid -s TYPE -o value "$LUKS")" = crypto_LUKS ] || die "$LUKS is not a LUKS partition"
ok "UEFI, $ESP (EFI) and $LUKS (LUKS) look right"

# --- 1. questions ----------------------------------------------------------------------
step "1. A few questions" \
"Everything personal is asked here, so nothing private lives in this script."
USERNAME=$(ask "Username (same as on the old system)")
HOSTNAME_NEW=$(ask "Hostname")
TIMEZONE=$(ask "Timezone, e.g. America/Los_Angeles")
[ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "unknown timezone: $TIMEZONE"
ok "user=$USERNAME host=$HOSTNAME_NEW tz=$TIMEZONE"

# --- 2. network ------------------------------------------------------------------------
step "2. Network" \
"pacstrap downloads packages, so we need internet. If you're not online yet, this
connects Wi-Fi with iwd (the ISO's Wi-Fi tool)."
if ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
    ok "already online"
else
    WIFI_DEV=""
    for d in /sys/class/net/wl*; do [ -e "$d" ] && WIFI_DEV=${d##*/} && break; done
    [ -n "$WIFI_DEV" ] || die "no Wi-Fi device found"
    SSID=$(ask "Wi-Fi name (SSID)")
    read -rsp "  Wi-Fi password: " PSK; echo
    iwctl --passphrase "$PSK" station "$WIFI_DEV" connect "$SSID"
    unset PSK
    for _ in 1 2 3 4 5 6 7 8 9 10; do ping -c1 -W2 archlinux.org >/dev/null 2>&1 && break; sleep 2; done
    ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "still offline; try: iwctl station $WIFI_DEV connect \"$SSID\""
    ok "online via $WIFI_DEV"
fi
timedatectl set-ntp true

# --- 3. unlock -------------------------------------------------------------------------
step "3. Unlock the existing encrypted partition" \
"Opens $LUKS with your EXISTING passphrase (the one you type at boot today). It appears
as /dev/mapper/$MAPPER. No luksFormat: the encryption and everything inside stay as-is."
if [ -b /dev/mapper/$MAPPER ]; then ok "already unlocked"; else cryptsetup open "$LUKS" "$MAPPER"; ok "unlocked"; fi

# --- 4. subvolumes ---------------------------------------------------------------------
step "4. Create the new subvolumes" \
"Mounts the top level of the btrfs filesystem, shows what's there (the old system's @,
@home, ...), and adds ${SUBVOLS[*]} next to them. Creating a subvolume is
like making a new folder: it doesn't touch the existing ones."
mkdir -p /mnt/top
mountpoint -q /mnt/top || mount -o subvolid=5 /dev/mapper/$MAPPER /mnt/top
echo "  Existing subvolumes:"; btrfs subvolume list /mnt/top | awk '{print "    "$NF}'
btrfs subvolume list /mnt/top | awk '{print $NF}' | grep -qx '@' || die "no @ subvolume: this isn't the disk layout this script expects"
existing=$(btrfs subvolume list /mnt/top | awk '{print $NF}')
if grep -qx '@arch' <<<"$existing"; then
    echo "  @arch already exists, probably from an earlier run that stopped halfway."
    read -rp "  Resume with the existing @arch* subvolumes? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { umount /mnt/top; die "stopped; nothing was changed"; }
else
    pause
fi
for s in "${SUBVOLS[@]}"; do
    if grep -qx "$s" <<<"$existing"; then ok "$s exists, reusing"
    else btrfs subvolume create "/mnt/top/$s" >/dev/null; ok "created $s"; fi
done
umount /mnt/top

# --- 5. mount --------------------------------------------------------------------------
step "5. Mount the new system at /mnt" \
"Assembles the future file tree: @arch becomes /, @arch-home becomes /home, and so on.
The shared EFI partition goes at /efi; the new system only adds its own two files there."
mount -o $MOUNT_OPTS,subvol=@arch /dev/mapper/$MAPPER /mnt
mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o $MOUNT_OPTS,subvol=@arch-home      /dev/mapper/$MAPPER /mnt/home
mount -o $MOUNT_OPTS,subvol=@arch-log       /dev/mapper/$MAPPER /mnt/var/log
mount -o $MOUNT_OPTS,subvol=@arch-pkg       /dev/mapper/$MAPPER /mnt/var/cache/pacman/pkg
mount -o $MOUNT_OPTS,subvol=@arch-snapshots /dev/mapper/$MAPPER /mnt/.snapshots
mount "$ESP" /mnt/efi
findmnt -R /mnt -o TARGET,SOURCE | sed 's/^/    /'
ok "mounted"

# --- 6. pacstrap -----------------------------------------------------------------------
step "6. Install the base system (pacstrap)" \
"Downloads and installs: ${PACKAGES[*]}
That's the kernel (+ LTS fallback), firmware, AMD microcode, btrfs tools, Wi-Fi,
sudo, fish, git, ssh, a readable console font and an editor. Takes a few minutes."
pause
pacstrap -K /mnt "${PACKAGES[@]}"
ok "base system installed"

# --- 7. fstab --------------------------------------------------------------------------
step "7. Write /etc/fstab" \
"Records what to mount at boot. Then checks it only mentions the new @arch* subvolumes
and /efi: no old-system subvolume and no swap (hibernation stays off until cutover)."
genfstab -U /mnt > /mnt/etc/fstab
sed 's/^/    /' /mnt/etc/fstab | grep -v '^    #' | grep -v '^    $'
grep -Eq 'subvol=/?@(home|log|pkg)?([,[:space:]]|$)' /mnt/etc/fstab && die "fstab mentions an old-system subvolume; fix /mnt/etc/fstab before going on"
grep -q '[[:space:]]swap[[:space:]]' /mnt/etc/fstab && die "fstab has a swap entry; remove it from /mnt/etc/fstab"
ok "fstab only has @arch* and /efi"

# --- 8. configure inside the new system ------------------------------------------------
LUKS_UUID=$(blkid -s UUID -o value "$LUKS")
step "8. Configure the new system (inside arch-chroot)" \
"Runs inside the new system: timezone, locale, console font, hostname, your user (you'll
set its password), sudo for the wheel group, NetworkManager with the iwd backend."
cat > /mnt/root/configure.sh <<EOF
set -euo pipefail
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
grep -qx 'en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
printf 'KEYMAP=us\nFONT=ter-132b\n' > /etc/vconsole.conf
echo '$HOSTNAME_NEW' > /etc/hostname
id -u '$USERNAME' >/dev/null 2>&1 || useradd -m -G wheel -s /usr/bin/fish '$USERNAME'
echo "  Set the password for $USERNAME:"
until passwd '$USERNAME'; do echo "  try again"; done
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi_backend.conf
systemctl enable NetworkManager >/dev/null 2>&1
EOF
arch-chroot /mnt bash /root/configure.sh
ok "configured"

# --- 9. kernel images ------------------------------------------------------------------
step "9. Build the kernel images (UKIs)" \
"Switches the initramfs to systemd's hooks (sd-encrypt asks for the LUKS passphrase at
boot, and later allows TPM unlock), writes the kernel command line (unlock $LUKS, root
on @arch), and builds one self-contained .efi per kernel on the EFI partition:
  /efi/EFI/Linux/arch-linux.efi and arch-linux-lts.efi
The old system's omarchy_*.efi files next to them are left alone."
cat > /mnt/root/kernel.sh <<EOF
set -euo pipefail
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
echo "rd.luks.name=$LUKS_UUID=root root=/dev/mapper/root rootflags=subvol=@arch rw" > /etc/kernel/cmdline
for k in linux linux-lts; do
  printf 'ALL_kver="/boot/vmlinuz-%s"\nPRESETS=(%s)\ndefault_uki="/efi/EFI/Linux/arch-%s.efi"\n' "\$k" "'default'" "\$k" > /etc/mkinitcpio.d/\$k.preset
done
rm -f /boot/initramfs-*.img
mkdir -p /efi/EFI/Linux
mkinitcpio -P
EOF
arch-chroot /mnt bash /root/kernel.sh
for k in linux linux-lts; do [ -s "/mnt/efi/EFI/Linux/arch-$k.efi" ] || die "arch-$k.efi was not built"; done
ls -la /mnt/efi/EFI/Linux/ | sed 's/^/    /'
ok "UKIs built"

# --- 10. boot entries ------------------------------------------------------------------
step "10. Add firmware boot entries" \
"Tells the laptop's firmware about the two new kernel images. 'Arch' goes first in the
boot order, so the laptop boots the new system by default. The old system stays in
the F12 menu. No bootloader yet; limine comes at cutover."
for entry in "Arch LTS:arch-linux-lts.efi" "Arch:arch-linux.efi"; do
    label=${entry%%:*}; file=${entry#*:}
    if efibootmgr | grep -qP "^Boot[0-9A-F]{4}\*? ${label}\t"; then ok "entry '$label' already exists"
    else efibootmgr --create --disk "$DISK" --part 1 --label "$label" --loader "\\EFI\\Linux\\$file" >/dev/null; ok "added '$label'"; fi
done
efibootmgr | sed 's/^/    /'

# --- 11. finish ------------------------------------------------------------------------
rm -f /mnt/root/configure.sh /mnt/root/kernel.sh
step "11. Done" \
"Unmounting. Next: type 'reboot', remove the USB stick, type the LUKS passphrase, log
in as $USERNAME, then follow the runbook's section 3 (first boot: get to Claude)."
umount -R /mnt
ok "all done"
