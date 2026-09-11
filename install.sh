#!/usr/bin/env bash
#
# Arch Linux installer — live ISO phase.
#
#   curl -fsSL https://raw.githubusercontent.com/philipp-bliznuk/arch-btw/master/install.sh -o install.sh
#   bash install.sh            # not `curl | bash` — needs interactive stdin
#
# Prompts: disk, timezone, username, LUKS/user/root passwords. Everything else hardcoded.
# Get online first (iwctl); saved iwd networks are carried into the installed system.
#
# Flags:  --skip-fido2   skip YubiKey enrollment (VM testing)
#         --phase chroot internal re-entry inside arch-chroot
# Debug:  DEBUG=1 bash install.sh

set -Eeuo pipefail

readonly HOSTNAME="arch-btw"
readonly LOCALE="en_US.UTF-8"
readonly KEYMAP="us"
readonly TIMEZONE_ROOT="/usr/share/zoneinfo"
readonly DOTFILES_HTTPS="https://github.com/philipp-bliznuk/arch-btw.git"
readonly LOG_FILE="/root/arch-install.log"

PACKAGES=(
	base linux linux-lts linux-firmware base-devel "<ucode>"
	mkinitcpio dbus-broker-units crun pipewire-jack          # explicit providers: initramfs, dbus-units, oci-runtime, jack
	git openssh btrfs-progs dosfstools neovim networkmanager # openssh = client only, no sshd
	pipewire pipewire-pulse wireplumber
	sudo zsh efibootmgr snapper snap-pac
	apparmor chrony firejail bubblewrap earlyoom ufw
	pacman-contrib
	polkit mesa sway swaylock swayidle quickshell
	wl-clipboard grim slurp ghostty xorg-xwayland
	xdg-desktop-portal-wlr xdg-desktop-portal-gtk
	ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
	brightnessctl playerctl xdg-user-dirs man-db man-pages
	bluez bluez-utils
	libqalculate systemd-ukify btrfs-assistant
	pam-u2f libfido2 yubikey-manager ccid pcsc-tools
	librewolf
	eza fzf fd ripgrep bat zoxide yazi ouch tmux fastfetch git-delta lazygit jujutsu podman
	poppler ffmpeg 7zip jq go-yq btop tree # go-yq = mikefarah yq
	tree-sitter-cli nodejs npm go python rustup uv bun
)

# --- helpers ---------------------------------------------------------------

_c() { printf '%s' "$(tput setaf "$1" 2>/dev/null || true)"; }
_r() { printf '%s' "$(tput sgr0 2>/dev/null || true)"; }
info() { printf '%s==>%s %s\n' "$(_c 4)" "$(_r)" "$*"; }
success() { printf '%s==>%s %s\n' "$(_c 2)" "$(_r)" "$*"; }
warn() { printf '%s==>%s %s\n' "$(_c 3)" "$(_r)" "$*" >&2; }
err() { printf '%s==>%s %s\n' "$(_c 1)" "$(_r)" "$*" >&2; }

pause() {
	local msg="${1:-Press Enter to continue}"
	printf '%s>>>%s %s' "$(_c 5)" "$(_r)" "$msg" >/dev/tty
	read -r </dev/tty
}

CURRENT_STEP=""

# Subshell: failure can't leave the parent half-applied; unexported vars stay visible.
run_step() {
	local step="$1"
	CURRENT_STEP="$step"
	info "$step"
	(
		trap - ERR
		[[ "${DEBUG:-0}" == "1" ]] && set -x
		PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: '
		"$step"
	) 2>&1 | tee -a "$LOG_FILE"
	return "${PIPESTATUS[0]}"
}

# Keep secrets out of `set -x` traces.
quiet_x() {
	[[ $- == *x* ]] && XTRACE_WAS_ON=1 || XTRACE_WAS_ON=0
	set +x
}
restore_x() { ((XTRACE_WAS_ON)) && set -x || true; }

on_error() {
	local ec=$?
	err "FAILED in step: ${CURRENT_STEP:-unknown} (exit $ec)"
	if [[ -f "$LOG_FILE" ]]; then
		err "last 20 log lines ($LOG_FILE):"
		tail -20 "$LOG_FILE" >&2 || true
	fi
	if [[ "${PHASE:-live}" == "live" && "${CURRENT_STEP:-}" != "step_finish" ]]; then
		err "Fix the cause and re-run install.sh. Re-running RE-WIPES ${DISK:-the target disk}."
	fi
	exit "$ec"
}
trap on_error ERR

# --- live-ISO steps --------------------------------------------------------

step_preflight() {
	[[ $EUID -eq 0 ]] || {
		err "Run as root from the live ISO."
		exit 1
	}
	[[ -d /run/archiso ]] || warn "Not /run/archiso — not the Arch live ISO? Continuing."
	[[ -d /sys/firmware/efi ]] || {
		err "Not booted in UEFI mode."
		exit 1
	}
	if bootctl status 2>/dev/null | grep -qi 'Secure Boot: enabled'; then
		err "Secure Boot is enabled. Disable it in firmware (leave it off), then reboot the ISO."
		exit 1
	fi

	timedatectl set-ntp true

	# Rerun safety.
	[[ -d /mnt/swap ]] && arch-chroot /mnt swapoff -a 2>/dev/null || true
	umount -R /mnt 2>/dev/null || true
	cryptsetup close cryptroot 2>/dev/null || true
}

step_network() {
	if curl -fsSI --max-time 5 https://archlinux.org >/dev/null 2>&1; then
		success "Online."
		return 0
	fi
	err "No connectivity. Connect first, then re-run:"
	echo "    iwctl station wlan0 scan" >/dev/tty
	echo "    iwctl station wlan0 get-networks" >/dev/tty
	echo '    iwctl station wlan0 connect "<SSID>"' >/dev/tty
	echo "  (station name: iwctl device list)" >/dev/tty
	exit 1
}

prompt_inputs() {
	CURRENT_STEP="prompt_inputs"
	info "Available disks:"
	mapfile -t _disks < <(lsblk -dpno NAME,SIZE,MODEL -e 7,11) # hide loop + sr
	local i
	for i in "${!_disks[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${_disks[$i]}"; done
	local n
	while :; do
		printf 'Target disk number (WIPED): ' >/dev/tty
		read -r n </dev/tty
		[[ "$n" =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#_disks[@]})) && break
		warn "Invalid selection."
	done
	DISK="$(awk '{print $1}' <<<"${_disks[$((n - 1))]}")"

	while :; do
		printf 'Timezone (e.g. Europe/Berlin): ' >/dev/tty
		read -r TIMEZONE </dev/tty
		[[ -f "$TIMEZONE_ROOT/$TIMEZONE" ]] && break
		warn "No such zone: $TIMEZONE_ROOT/$TIMEZONE"
	done

	while :; do
		printf 'Username: ' >/dev/tty
		read -r USERNAME </dev/tty
		[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] && break
		warn "Must match ^[a-z_][a-z0-9_-]*$"
	done

	LUKS_PASS="$(_read_confirmed 'LUKS passphrase')"
	USER_PASS="$(_read_confirmed 'user password')"
	ROOT_PASS="$(_read_confirmed 'root password')"

	_summary
}

_read_confirmed() {
	local label="$1" a b
	while :; do
		printf 'Enter %s: ' "$label" >/dev/tty
		read -rs a </dev/tty
		printf '\n' >/dev/tty
		printf 'Confirm %s: ' "$label" >/dev/tty
		read -rs b </dev/tty
		printf '\n' >/dev/tty
		[[ -n "$a" && "$a" == "$b" ]] && {
			printf '%s' "$a"
			return 0
		}
		warn "Empty or mismatch — try again."
	done
}

_summary() {
	local mask
	mask="$(printf '%*s' 8 '' | tr ' ' '*')"
	cat >/dev/tty <<EOF

  ---------------------------------------------
   Disk        : $DISK   (ALL DATA ERASED)
   Hostname    : $HOSTNAME
   Timezone    : $TIMEZONE
   Username    : $USERNAME
   Microcode   : $UCODE
   Swap        : ${SWAP_GB}G (RAM-sized, hibernation)
   LUKS pass   : $mask
   User pass   : $mask
   Root pass   : $mask
   FIDO2       : $( ((SKIP_FIDO2)) && echo 'skipped (--skip-fido2)' || echo 'enroll 2 keys')
  ---------------------------------------------

EOF
	local ans
	printf 'Type YES to wipe %s and continue: ' "$DISK" >/dev/tty
	read -r ans </dev/tty
	[[ "$ans" == "YES" ]] || {
		err "Aborted."
		exit 1
	}
}

detect_ucode() {
	if grep -qm1 'GenuineIntel' /proc/cpuinfo; then UCODE="intel-ucode"; else UCODE="amd-ucode"; fi
	info "Microcode: $UCODE"
}

detect_swap_gb() {
	# >= RAM for hibernation; rounded up to GiB.
	local kb
	kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
	SWAP_GB=$(((kb + 1048575) / 1048576))
	info "Swap size: ${SWAP_GB}G"
}

part_suffix() {
	[[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]] && printf '%sp' "$DISK" || printf '%s' "$DISK"
}

derive_parts() {
	local base
	base="$(part_suffix)"
	PART_ESP="${base}1"
	PART_LUKS="${base}2"
}

step_partition() {
	sgdisk --zap-all "$DISK"
	sgdisk -n1:0:+2G -t1:ef00 -c1:EFI "$DISK"
	sgdisk -n2:0:0 -t2:8309 -c2:LUKS "$DISK"
	partprobe "$DISK"
	udevadm settle
	[[ -b "$PART_ESP" && -b "$PART_LUKS" ]] || {
		err "Partition nodes not present: $PART_ESP $PART_LUKS"
		exit 1
	}
	mkfs.fat -F32 "$PART_ESP"
}

step_luks() {
	quiet_x
	printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 -q --key-file=- "$PART_LUKS"
	printf '%s' "$LUKS_PASS" | cryptsetup open --key-file=- "$PART_LUKS" cryptroot
	restore_x
}

step_btrfs() {
	mkfs.btrfs -f /dev/mapper/cryptroot
	mount /dev/mapper/cryptroot /mnt
	btrfs subvol create /mnt/@
	btrfs subvol create /mnt/@home
	btrfs subvol create /mnt/@snapshots
	btrfs subvol create /mnt/@swap # btrfs can't snapshot an active swapfile
	umount /mnt

	mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
	mkdir -p /mnt/{home,.snapshots,swap,boot/efi}
	mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
	mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
	mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap
	mount -o umask=0077 "$PART_ESP" /mnt/boot/efi # ESP holds the boot random seed
}

step_fido2() {
	CURRENT_STEP="step_fido2"
	if ((SKIP_FIDO2)); then
		warn "Skipping FIDO2 enrollment (--skip-fido2)."
		return 0
	fi

	local k
	for k in 1 2; do
		pause "Insert YubiKey #$k ONLY (remove the other), then Enter"
		# Asks FIDO2 PIN + touch on the tty despite --fido2-with-client-pin=no (CTAP2 credential creation).
		until _enroll_fido2; do
			warn "Enrollment of key #$k failed."
			pause "Check the key is inserted (and the other removed), then Enter to retry"
		done
		success "Key #$k enrolled."
	done
	if cryptsetup luksDump "$PART_LUKS" | grep -q 'fido2'; then
		success "FIDO2 keyslots present."
	else
		err "No fido2 token found in the LUKS header after enrollment."
		exit 1
	fi
}

_enroll_fido2() {
	local rc
	quiet_x
	PASSWORD="$LUKS_PASS" systemd-cryptenroll \
		--fido2-device=auto --fido2-with-client-pin=no "$PART_LUKS" && rc=0 || rc=$?
	restore_x
	return "$rc"
}

step_pacstrap() {
	pacman -Sy --noconfirm archlinux-keyring # stale ISO keyring → signature failures
	local pkgs=("${PACKAGES[@]/<ucode>/$UCODE}")
	# Pre-create vconsole.conf: silences mkinitcpio "not found" warning during pacstrap's stock image build
	mkdir -p /mnt/etc
	echo "KEYMAP=${KEYMAP}" >/mnt/etc/vconsole.conf
	# SNAP_PAC_SKIP: snap-pac hook calls `ps` → "fatal library error, lookup self" in chroot (harmless)
	SNAP_PAC_SKIP=yes pacstrap -K /mnt "${pkgs[@]}"
	genfstab -U /mnt >>/mnt/etc/fstab
	grep -qE 'subvol=/?@' /mnt/etc/fstab || { # kernel reports subvol=/@
		err "fstab missing subvol entries."
		exit 1
	}
}

step_chroot() {
	cp "${BASH_SOURCE[0]}" /mnt/root/install.sh
	arch-chroot -S /mnt env \
		TIMEZONE="$TIMEZONE" HOSTNAME="$HOSTNAME" LOCALE="$LOCALE" KEYMAP="$KEYMAP" \
		USERNAME="$USERNAME" SWAP_GB="$SWAP_GB" LUKS_UUID="$LUKS_UUID" \
		DEBUG="${DEBUG:-0}" \
		bash /root/install.sh --phase chroot

	quiet_x
	printf 'root:%s\n%s:%s\n' "$ROOT_PASS" "$USERNAME" "$USER_PASS" |
		arch-chroot /mnt chpasswd
	restore_x
	success "Passwords set."
}

step_dotfiles_clone() {
	# runuser keeps HOME=/root → git EACCES on /root/.gitconfig; set HOME explicitly.
	local home="/home/$USERNAME"
	arch-chroot /mnt runuser -u "$USERNAME" -- env HOME="$home" \
		git clone "$DOTFILES_HTTPS" "$home/projects/dotfiles"
	arch-chroot /mnt runuser -u "$USERNAME" -- env HOME="$home" touch "$home/.zshrc" # silences zsh-newuser-install
}

# iwd /var/lib/iwd/<SSID>.psk → NetworkManager keyfiles so Wi-Fi works on first boot.
_harvest_wifi() {
	local f base ssid psk nm
	shopt -s nullglob
	for f in /var/lib/iwd/*.psk; do
		base="$(basename "$f" .psk)"
		if [[ "$base" == =* ]]; then # iwd hex-encodes SSIDs with chars outside [A-Za-z0-9 _-]
			ssid="$(printf '%b' "$(sed 's/^=//; s/../\\x&/g' <<<"$base")")"
		else
			ssid="$base"
		fi
		psk="$(awk -F= '/^Passphrase=/{sub(/^Passphrase=/,""); print; exit}' "$f")"
		[[ -n "$psk" ]] || psk="$(awk -F= '/^PreSharedKey=/{sub(/^PreSharedKey=/,""); print; exit}' "$f")"
		[[ -n "$psk" ]] || continue

		nm="/mnt/etc/NetworkManager/system-connections/${ssid}.nmconnection"
		mkdir -p "$(dirname "$nm")"
		cat >"$nm" <<EOF
[connection]
id=$ssid
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto

[ipv6]
method=auto
EOF
		chmod 600 "$nm"
		success "Wi-Fi profile saved for first boot: $ssid"
	done
	shopt -u nullglob
}

step_finish() {
	CURRENT_STEP="step_finish"
	_harvest_wifi
	ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf # impossible inside arch-chroot (bind mount)

	cp "$LOG_FILE" /mnt/var/log/arch-install.log 2>/dev/null || true
	rm -f /mnt/root/install.sh

	arch-chroot /mnt swapoff -a 2>/dev/null || true # kernel records chroot-relative swap path
	umount -R /mnt
	cryptsetup close cryptroot

	success "Install complete."
	echo
	echo "  Next:"
	echo "    1. reboot (remove the USB)"
	echo "    2. unlock LUKS (passphrase, or insert+touch a YubiKey)"
	echo "    3. log in on TTY2 (Ctrl-Alt-F2) as $USERNAME"
	echo "    4. run: ~/projects/dotfiles/post-install.sh"
	echo
	pause "Press Enter to reboot now (or Ctrl-C to stay)"
	reboot
}

# --- chroot phase ----------------------------------------------------------

chroot_phase() {
	CURRENT_STEP="chroot_phase"
	if [[ "${DEBUG:-0}" == "1" ]]; then
		PS4='+ chroot:${LINENO}:${FUNCNAME[0]:-main}: '
		set -x
	fi

	ln -sf "$TIMEZONE_ROOT/$TIMEZONE" /etc/localtime
	hwclock --systohc
	echo "$LOCALE UTF-8" >>/etc/locale.gen
	locale-gen
	echo "LANG=$LOCALE" >/etc/locale.conf
	echo "KEYMAP=$KEYMAP" >/etc/vconsole.conf # required by sd-vconsole

	echo "$HOSTNAME" >/etc/hostname
	cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

	# No swapon here — active swap would block the final umount.
	btrfs filesystem mkswapfile --uuid clear --size "${SWAP_GB}G" /swap/swapfile
	echo "/swap/swapfile none swap defaults 0 0" >>/etc/fstab
	local offset
	offset="$(btrfs inspect-internal map-swapfile -r /swap/swapfile)" # not filefrag on btrfs

	# systemd hook family only — never mix with busybox encrypt/keymap.
	sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' \
		/etc/mkinitcpio.conf

	# discard: TRIM through dm-crypt so fstrim.timer works. No lockdown= — breaks hibernation.
	mkdir -p /etc/cmdline.d
	cat >/etc/cmdline.d/root.conf <<EOF
rd.luks.name=${LUKS_UUID}=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet lsm=landlock,lockdown,yama,apparmor,bpf rd.luks.options=${LUKS_UUID}=fido2-device=auto,discard
EOF
	cat >/etc/cmdline.d/resume.conf <<EOF
resume=/dev/mapper/cryptroot resume_offset=${offset}
EOF

	_write_presets
	_write_system_config

	rm -f /boot/initramfs-*.img # pacstrap built classic images with the stock preset
	bootctl install
	mkdir -p /boot/efi/EFI/Linux
	mkinitcpio -p linux
	mkinitcpio -p linux-lts

	systemctl enable NetworkManager apparmor earlyoom chronyd systemd-resolved
	systemctl enable systemd-boot-update.service # no pacman hook for systemd-boot on Arch
	systemctl enable snapper-timeline.timer snapper-cleanup.timer
	systemctl enable fstrim.timer paccache.timer

	useradd -m -G wheel -s /bin/zsh "$USERNAME"
	grep -q "^${USERNAME}:" /etc/subuid || # rootless podman
		usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USERNAME"
	mkdir -p /etc/sudoers.d
	echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

_write_presets() {
	local k
	for k in linux linux-lts; do
		cat >"/etc/mkinitcpio.d/${k}.preset" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${k}"

PRESETS=('default' 'fallback')

default_uki="/boot/efi/EFI/Linux/arch-${k}.efi"

fallback_uki="/boot/efi/EFI/Linux/arch-${k}-fallback.efi"
fallback_options="-S autodetect"
EOF
	done
}

_write_system_config() {
	cat >/etc/sysctl.d/99-hardening.conf <<'EOF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.tcp_syncookies = 1
EOF

	mkdir -p /etc/systemd/resolved.conf.d
	cat >/etc/systemd/resolved.conf.d/00-quad9.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
Domains=~.
EOF

	sed -i -E 's/^(pool|server) /#&/' /etc/chrony.conf # Arch ships either form
	cat >>/etc/chrony.conf <<'EOF'
server time.cloudflare.com iburst nts
minsources 1
EOF

	mkdir -p /etc/systemd/journald.conf.d
	cat >/etc/systemd/journald.conf.d/00-size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
EOF

	mkdir -p /etc/systemd/sleep.conf.d
	cat >/etc/systemd/sleep.conf.d/00-hibernate-delay.conf <<'EOF'
[Sleep]
HibernateDelaySec=1h
EOF

	mkdir -p /etc/systemd/logind.conf.d
	cat >/etc/systemd/logind.conf.d/00-lid.conf <<'EOF'
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
HandleLidSwitchDocked=ignore
EOF

	# Non-Mono variant on purpose — Mono clips icons.
	cat >/etc/fonts/local.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Noto Serif</family></prefer>
  </alias>
</fontconfig>
EOF
}

# --- entry -----------------------------------------------------------------

main_live() {
	: >"$LOG_FILE"
	info "Arch install — live ISO phase. Log: $LOG_FILE"

	run_step step_preflight
	run_step step_network
	detect_ucode
	detect_swap_gb
	prompt_inputs # interactive — outside run_step
	derive_parts
	run_step step_partition
	run_step step_luks
	LUKS_UUID="$(blkid -s UUID -o value "$PART_LUKS")"
	run_step step_btrfs
	step_fido2 # interactive — outside run_step
	run_step step_pacstrap
	run_step step_chroot
	run_step step_dotfiles_clone
	step_finish # interactive — outside run_step
}

SKIP_FIDO2=0
PHASE="live"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip-fido2)
		SKIP_FIDO2=1
		shift
		;;
	--phase)
		PHASE="$2"
		shift 2
		;;
	*)
		err "Unknown argument: $1"
		exit 1
		;;
	esac
done

case "$PHASE" in
live) main_live ;;
chroot) chroot_phase ;;
*)
	err "Unknown phase: $PHASE"
	exit 1
	;;
esac
