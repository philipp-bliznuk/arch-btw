#!/usr/bin/env bash
#
# Arch Linux installer - live ISO phase.
#
#   curl -fsSL https://raw.githubusercontent.com/philipp-bliznuk/arch-btw/master/install.sh -o install.sh
#   bash install.sh            # not `curl | bash` - needs interactive stdin
#
# Prompts: disk, timezone, username, LUKS/user/root passwords. Everything else hardcoded.
# Get online first (iwctl); saved iwd networks are carried into the installed system.
#
# Flags:  --skip-fido2   skip YubiKey enrollment (VM testing)
#         --phase chroot internal re-entry inside arch-chroot
# Debug:  DEBUG=1 bash install.sh

# Whole body wrapped in { } so a truncated download is a syntax error, not a half-run install.
{
set -Eeuo pipefail

readonly HOSTNAME="arch-btw"
readonly LOCALE="en_US.UTF-8"
readonly KEYMAP="us"
readonly TIMEZONE_ROOT="/usr/share/zoneinfo"
readonly DOTFILES_HTTPS="https://github.com/philipp-bliznuk/arch-btw.git"
readonly LOG_FILE="/root/arch-install.log"
readonly TPM_EVENTLOG="/sys/kernel/security/tpm0/binary_bios_measurements"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

PACKAGES=(
	base linux linux-lts linux-firmware base-devel "<ucode>"
	mkinitcpio dbus-broker-units crun pipewire-jack          # explicit providers: initramfs, dbus-units, oci-runtime, jack
	git openssh btrfs-progs dosfstools neovim networkmanager # openssh: client use, sshd.service never enabled
	pipewire pipewire-pulse wireplumber
	sudo zsh efibootmgr sbctl snapper snap-pac arch-install-scripts # sbctl: Secure Boot keys, its mkinitcpio post hook signs every UKI built; arch-chroot: bin/snap-restore rebuilds the UKIs inside the restored root
	apparmor chrony firejail xdg-dbus-proxy earlyoom ufw # xdg-dbus-proxy: without it firejail downgrades every dbus-user filter to allow
	pacman-contrib
	polkit mesa sway swaylock swayidle quickshell upower cmatrix
	"<vaapi>" # hardware video decode (browser video otherwise burns a CPU core + GPU uploads)
	wl-clipboard grim slurp kitty xorg-xwayland
	xdg-desktop-portal-wlr xdg-desktop-portal-gtk
	ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji # cjk: fallback glyphs for app menus/titles (tray menus, window titles)
	brightnessctl ddcutil xdg-user-dirs man-db man-pages # ddcutil: brightness keys on an external monitor over DDC/CI (bin/qs-brightness)
	wireless-regdb kernel-modules-hook udisks2 # Wi-Fi rules for the timezone's country; the running kernel's modules survive an upgrade; udisksctl mounts USB/SD as the user, no automount
	wlsunset power-profiles-daemon # night light (qs-toggle), battery power profiles (Quickshell battery popup talks D-Bus, no powerprofilesctl)
	libqalculate
	pam-u2f libfido2 yubikey-manager ccid
	kguiaddons kwindowsystem # pinentry-qt links against these (gpg passphrase prompt)
	qt6ct adw-gtk-theme      # Catppuccin for Qt (qt6ct palette) and GTK 3/4 (adw-gtk3 + gtk/gtk.css named colours)
	librewolf imv mpv # imv/mpv: the only image and video handlers for xdg-open (LibreWolf registers neither); Setup > Default apps picks
	xdg-utils desktop-file-utils # xdg-mime, update-desktop-database (bin/qs-defaults, post-install.sh); deps of qt6-base and gtk3 anyway
	eza fzf fd ripgrep bat zoxide yazi ouch tmux fastfetch git-delta lazygit jujutsu podman
	poppler ffmpeg 7zip unzip jq go-yq btop tree # go-yq = mikefarah yq; unzip: mason unpacks stylua with it
	tree-sitter-cli nodejs npm go python uv bun
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

# SetupMode: 4 attribute bytes, then 1 = no Platform Key, so the firmware takes
# new keys and verifies nothing yet (README, Step 0). Readable on the ISO and
# inside the chroot (/sys is bind-mounted).
_setup_mode() {
	local v=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
	[[ -r $v && "$(od -An -tu1 -j4 -N1 "$v" | tr -d ' ')" == 1 ]]
}

# What _secure_boot will get to, for the summary.
_sb_plan() {
	_setup_mode || { echo 'not in Setup Mode - UKIs signed, enroll later'; return 0; }
	[[ -e $TPM_EVENTLOG ]] || { echo 'no TPM event log - UKIs signed, enroll later'; return 0; }
	echo 'Setup Mode - own keys enrolled'
}

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
	[[ -d /run/archiso ]] || warn "Not /run/archiso - not the Arch live ISO? Continuing."
	[[ -d /sys/firmware/efi ]] || {
		err "Not booted in UEFI mode."
		exit 1
	}
	# Captured, not piped: bootctl exits 1 on the ISO (no ESP yet) and pipefail
	# would turn a matching grep into a pass.
	if [[ "$(bootctl status 2>/dev/null || true)" == *"Secure Boot: enabled"* ]]; then
		err "Secure Boot is enforcing. Reset to Setup Mode in firmware (README, Step 0), then reboot the ISO."
		exit 1
	fi
	# sbctl enroll-keys reads the TPM event log for option ROMs the keys would
	# lock out and refuses without one (TPM off in firmware): keys and signed
	# UKIs still happen, enrollment does not.
	[[ -e $TPM_EVENTLOG ]] ||
		warn "No TPM event log: the Secure Boot keys will not be enrolled. TPM on in firmware (README, Step 0) for an enforcing install."

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
	# Hide loop and sr devices, the stick the ISO runs from, and empty card
	# readers (0B). bootmnt is that stick, one of its partitions, or Ventoy's
	# device-mapper image of the ISO on it: the inverse tree ends at the disk
	# in every case.
	local iso_src iso_disk=""
	iso_src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
	[[ -b "$iso_src" ]] && iso_disk="$(lsblk -slpno NAME "$iso_src" | tail -1)"
	mapfile -t _disks < <(lsblk -dpno NAME,SIZE,MODEL -e 7,11 | awk -v skip="$iso_disk" '$1 != skip && $2 != "0B"')
	[[ ${#_disks[@]} -gt 0 ]] || {
		err "No target disk found."
		exit 1
	}
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
		[[ -f "$TIMEZONE_ROOT/$TIMEZONE" ]] || {
			warn "No such zone: $TIMEZONE_ROOT/$TIMEZONE"
			continue
		}
		[[ "$TIMEZONE" == UTC || "$TIMEZONE" == Etc/* ]] && break
		# zone.tab lists canonical names only; it is where the Wi-Fi regulatory domain's country comes from
		awk -v tz="$TIMEZONE" '$3 == tz { found = 1 } END { exit !found }' "$TIMEZONE_ROOT/zone.tab" && break
		warn "$TIMEZONE is an alias (tzdata 'backward' link); use the canonical name from $TIMEZONE_ROOT/zone.tab"
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
		IFS= read -rs a </dev/tty
		printf '\n' >/dev/tty
		printf 'Confirm %s: ' "$label" >/dev/tty
		IFS= read -rs b </dev/tty
		printf '\n' >/dev/tty
		[[ -n "$a" && "$a" == "$b" ]] && {
			printf '%s' "$a"
			return 0
		}
		warn "Empty or mismatch - try again."
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
   VA-API      : $VAAPI
   Swap        : ${SWAP_GB}G (RAM-sized, hibernation)
   LUKS pass   : $mask
   User pass   : $mask
   Root pass   : $mask
   FIDO2       : $( ((SKIP_FIDO2)) && echo 'skipped (--skip-fido2)' || echo 'enroll 2 keys')
   Secure Boot : $(_sb_plan)
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
	if grep -qm1 'GenuineIntel' /proc/cpuinfo; then
		UCODE="intel-ucode"
		VAAPI="intel-media-driver" # iHD: Broadwell+; older Intel would need libva-intel-driver
	else
		UCODE="amd-ucode"
		VAAPI="libva-mesa-driver"
	fi
	info "Microcode: $UCODE · VA-API: $VAAPI"
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
		until _fido2_pin_notice && _enroll_fido2; do
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

# The FIDO2 PIN (ykman fido access change-pin) is asked here and at every boot.
# It is not the OpenPGP PIN. Three wrong in a row lock the applet until the key
# is replugged, eight wrong in total wipe it (ykman fido reset).
_fido2_pin_notice() {
	local dev retries
	dev="$(fido2-token -L 2>/dev/null | head -1 | cut -d: -f1)"
	retries="$(fido2-token -I "$dev" 2>/dev/null | awk -F': ' '/^pin retries/ {print $2}')"
	warn "Next prompt: FIDO2 PIN (not the OpenPGP PIN), then touch. PIN retries left: ${retries:-unknown}."
}

_enroll_fido2() {
	local rc
	quiet_x
	PASSWORD="$LUKS_PASS" systemd-cryptenroll \
		--fido2-device=auto --fido2-with-client-pin=yes "$PART_LUKS" && rc=0 || rc=$?
	restore_x
	return "$rc"
}

step_pacstrap() {
	pacman -Sy --noconfirm archlinux-keyring # stale ISO keyring → signature failures
	local pkgs=("${PACKAGES[@]/<ucode>/$UCODE}")
	pkgs=("${pkgs[@]/<vaapi>/$VAAPI}")
	# vconsole.conf before pacstrap: sd-vconsole needs it, and the stock image
	# build during pacstrap warns "not found" without it
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
		TIMEZONE="$TIMEZONE" USERNAME="$USERNAME" SWAP_GB="$SWAP_GB" LUKS_UUID="$LUKS_UUID" \
		DEBUG="${DEBUG:-0}" \
		bash /root/install.sh --phase chroot

	quiet_x
	printf 'root:%s\n%s:%s\n' "$ROOT_PASS" "$USERNAME" "$USER_PASS" |
		arch-chroot /mnt chpasswd
	restore_x
	success "Passwords set."
}

# Firmware entries straight to the UKIs (efibootmgr is on the ISO, sbctl is
# not, so this is the one Secure Boot piece outside the chroot). Each new
# entry goes to the head of BootOrder, so the LTS one is created first and
# "Arch Linux" boots by default; F12 offers the other.
step_boot_entries() {
	if ! { efibootmgr -q -c -d "$DISK" -p 1 -L "Arch Linux LTS" -l '\EFI\BOOT\BOOTX64.EFI' &&
		efibootmgr -q -c -d "$DISK" -p 1 -L "Arch Linux" -l '\EFI\Linux\arch-linux.efi' &&
		efibootmgr | grep -E '^Boot(Order|[0-9A-F]{4}\* Arch Linux)'; }; then
		warn "Boot entries not written (NVRAM full, or the firmware refused). Without them the firmware falls back to EFI/BOOT/BOOTX64.EFI, the LTS UKI; post-install step bootloader recreates both."
	fi
}

step_dotfiles_clone() {
	# runuser keeps HOME=/root → git EACCES on /root/.gitconfig; set HOME explicitly.
	local home="/home/$USERNAME"
	if [[ -f "$SCRIPT_DIR/post-install.sh" && -d "$SCRIPT_DIR/.git" ]]; then
		# Running from a local checkout (VM/branch testing): install that tree instead of cloning master.
		info "Using local dotfiles checkout: $SCRIPT_DIR"
		mkdir -p "/mnt$home/projects"
		git clone --quiet "$SCRIPT_DIR" "/mnt$home/projects/dotfiles"
		git -C "/mnt$home/projects/dotfiles" remote set-url origin "$DOTFILES_HTTPS"
		arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "$home/projects"
	else
		arch-chroot /mnt runuser -u "$USERNAME" -- env HOME="$home" \
			git clone "$DOTFILES_HTTPS" "$home/projects/dotfiles"
	fi
	arch-chroot /mnt runuser -u "$USERNAME" -- env HOME="$home" touch "$home/.zshrc" # silences zsh-newuser-install
}

# iwd /var/lib/iwd/<SSID>.psk → NetworkManager keyfiles so Wi-Fi works on first
# boot. WPA-PSK only: iwd keeps 802.1X networks in *.8021x, not carried over.
_harvest_wifi() {
	local f base ssid psk nm
	shopt -s nullglob
	local psks=(/var/lib/iwd/*.psk)
	[[ ${#psks[@]} -gt 0 ]] || warn "No iwd WPA-PSK profile in /var/lib/iwd - Wi-Fi needs setting up on first boot."
	for f in "${psks[@]}"; do
		base="$(basename "$f" .psk)"
		if [[ "$base" == =* ]]; then # iwd hex-encodes SSIDs with chars outside [A-Za-z0-9 _-]
			ssid="$(printf '%b' "$(sed 's/^=//; s/../\\x&/g' <<<"$base")")"
		else
			ssid="$base"
		fi
		psk="$(awk -F= '/^Passphrase=/{sub(/^Passphrase=/,""); print; exit}' "$f")"
		[[ -n "$psk" ]] || psk="$(awk -F= '/^PreSharedKey=/{sub(/^PreSharedKey=/,""); print; exit}' "$f")"
		[[ -n "$psk" ]] || continue

		# File named after iwd's encoded form: the decoded SSID may hold "/".
		nm="/mnt/etc/NetworkManager/system-connections/${base}.nmconnection"
		mkdir -p "$(dirname "$nm")"
		(
			umask 077
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
		)
		success "Wi-Fi profile saved for first boot: $ssid"
	done
	shopt -u nullglob
}

step_finish() {
	CURRENT_STEP="step_finish"
	_harvest_wifi
	ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf # impossible inside arch-chroot (bind mount)

	install -m 600 "$LOG_FILE" /mnt/var/log/arch-install.log 2>/dev/null || true
	rm -f /mnt/root/install.sh

	arch-chroot /mnt swapoff -a 2>/dev/null || true # kernel records chroot-relative swap path
	umount -R /mnt
	cryptsetup close cryptroot

	success "Install complete."
	echo
	echo "  Next:"
	echo "    1. reboot (remove the USB)"
	echo "    2. unlock LUKS (YubiKey: FIDO2 PIN + touch; no key: passphrase)"
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

	# No /etc/hosts entries: nss-myhostname and resolved answer for localhost
	# and the hostname (nsswitch: resolve [!UNAVAIL=return] files myhostname).
	echo "$HOSTNAME" >/etc/hostname

	# No swapon here - active swap would block the final umount.
	btrfs filesystem mkswapfile --uuid clear --size "${SWAP_GB}G" /swap/swapfile
	echo "/swap/swapfile none swap defaults 0 0" >>/etc/fstab
	local offset
	offset="$(btrfs inspect-internal map-swapfile -r /swap/swapfile)" # not filefrag on btrfs

	# systemd hook family only - never mix with busybox encrypt/keymap.
	sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' \
		/etc/mkinitcpio.conf
	grep -q '^HOOKS=(base systemd .* sd-encrypt ' /etc/mkinitcpio.conf || {
		err "mkinitcpio.conf: HOOKS not rewritten."
		exit 1
	}

	# discard: TRIM through dm-crypt so fstrim.timer works. No lockdown= - breaks hibernation.
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
	# No boot loader: the firmware runs the UKIs itself (entries: step_boot_entries).
	mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/Linux
	mkinitcpio -p linux
	mkinitcpio -p linux-lts
	_secure_boot

	sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf # policies: /etc/default/ufw (INPUT DROP, OUTPUT ACCEPT)
	grep -q '^ENABLED=yes' /etc/ufw/ufw.conf || {
		err "ufw.conf: ENABLED=yes not set."
		exit 1
	}
	systemctl enable NetworkManager apparmor earlyoom chronyd systemd-resolved upower power-profiles-daemon ufw
	systemctl enable linux-modules-cleanup.service # drops the modules kernel-modules-hook kept for the previous kernel
	systemctl mask sshd-unix-local.socket # systemd-ssh-generator starts it on every boot once sshd is installed (AF_UNIX, password stack)
	systemctl enable snapper-timeline.timer snapper-cleanup.timer
	systemctl enable fstrim.timer paccache.timer

	useradd -m -k /dev/null -G wheel -s /bin/zsh "$USERNAME" # no /etc/skel bash files, the shell is zsh
	grep -q "^${USERNAME}:" /etc/subuid || # rootless podman
		usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USERNAME"
	# tty1 is $USERNAME's console: login runs for that name without asking it, so
	# a boot is LUKS, then one touch (pam_u2f in login, post-install) or the
	# password. Not autologin: login still authenticates. Other VTs keep the prompt.
	mkdir -p /etc/systemd/system/getty@tty1.service.d
	cat >/etc/systemd/system/getty@tty1.service.d/skip-login.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -o '-- $USERNAME' --skip-login --noreset --noclear - \${TERM}
EOF
	# nothing to type before login starts, so its 60 s timer would restart it
	# every minute at an unattended tty1 (key blinking 29 s of each)
	sed -i 's/^LOGIN_TIMEOUT.*/LOGIN_TIMEOUT\t\t0/' /etc/login.defs
	grep -q '^LOGIN_TIMEOUT[[:space:]]*0$' /etc/login.defs || {
		err "login.defs: LOGIN_TIMEOUT 0 not set."
		exit 1
	}
	mkdir -p /etc/sudoers.d
	echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

_write_presets() {
	# The LTS UKI sits at the removable-media path a firmware tries with no
	# entry at all (F12 picks it by name otherwise); the main one is the default entry.
	local k
	local -A uki=([linux]="/boot/efi/EFI/Linux/arch-linux.efi" [linux-lts]="/boot/efi/EFI/BOOT/BOOTX64.EFI")
	for k in linux linux-lts; do
		cat >"/etc/mkinitcpio.d/${k}.preset" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${k}"

PRESETS=('default')

default_uki="${uki[$k]}"
EOF
	done
}

# Keys for this machine alone: the firmware will trust nothing else, Microsoft's
# included. Created after the builds so `sign -s` records both UKIs in sbctl's
# database (an already signed file is skipped before the database write); from
# here on the mkinitcpio post hook signs every rebuild. Enrolling needs Setup
# Mode; without it the system boots with Secure Boot off until enrolled.
_secure_boot() {
	sbctl create-keys
	sbctl sign -s /boot/efi/EFI/Linux/arch-linux.efi
	sbctl sign -s /boot/efi/EFI/BOOT/BOOTX64.EFI
	ESP_PATH=/boot/efi sbctl verify || warn "sbctl verify failed to list the ESP; run sbctl verify after the first boot."
	_setup_mode || {
		warn "Firmware not in Setup Mode: keys not enrolled. Later: Reset to Setup Mode, boot, sudo sbctl enroll-keys -i (README, Recovery)."
		return 0
	}
	# Never --microsoft (the point) and never --yes-this-might-brick-my-machine:
	# sbctl stops when the TPM event log shows an option ROM the keys would lock out.
	sbctl enroll-keys -i || warn "Keys not enrolled (see above): Secure Boot stays off until sudo sbctl enroll-keys -i succeeds. No TPM event log means the chip is off (README, Step 0); an option ROM in it takes -i --tpm-eventlog (README, Recovery)."
}

_write_system_config() {
	cat >/etc/sysctl.d/99-hardening.conf <<'EOF'
kernel.kptr_restrict = 2
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
EOF

	# Wi-Fi regulatory domain = the timezone's country (zone.tab); zones without
	# one (UTC, Etc/*) keep the world domain, which is what the kernel has
	# without a regulatory.db at all: fewer 5 GHz channels, lower power. Intel
	# LAR firmware (`iw reg get`: self-managed) takes the country from the AP
	# and ignores this; the global domain covers adapters without that.
	local country
	country="$(awk -v tz="$TIMEZONE" '$3 == tz { print $1; exit }' /usr/share/zoneinfo/zone.tab)"
	if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
		echo "WIRELESS_REGDOM=\"$country\"" >>/etc/conf.d/wireless-regdom
	fi

	# Thresholds stay at -m 10 -s 10: with a RAM-sized swapfile that is "RAM and
	# swap both nearly gone", a few hundred MB before the kernel's own OOM killer,
	# but SIGTERM first, the compositor and the shell last (--avoid takes 300 off
	# their oom_score). Browser content processes go first: a tab reload is the
	# cheapest loss. No -n: its D-Bus notifications need systembus-notify running
	# as the user, which is not installed.
	cat >/etc/default/earlyoom <<'EOF'
# Written by install.sh.
EARLYOOM_ARGS="-r 3600 --avoid '^(systemd|sway|quickshell)$' --prefer '^(Isolated Web Co|Web Content)$'"
EOF

	# udisks2 lets the active session mount removable media without a prompt
	# (polkit allow_active). The same default on loop-setup would let any
	# session process hand a file it wrote to the kernel's filesystem parsers
	# as root; that, and format/partition changes (modify-device), take an
	# admin auth instead: the polkit agent, pam_u2f, one touch.
	cat >/etc/polkit-1/rules.d/10-udisks2.rules <<'EOF'
// Written by install.sh.
polkit.addRule(function (action, subject) {
    if (action.id == "org.freedesktop.udisks2.loop-setup" ||
        action.id == "org.freedesktop.udisks2.modify-device") {
        return polkit.Result.AUTH_ADMIN_KEEP;
    }
});
EOF

	mkdir -p /etc/systemd/resolved.conf.d
	cat >/etc/systemd/resolved.conf.d/00-quad9.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
Domains=~.
LLMNR=no
MulticastDNS=no
EOF

	sed -i -E 's/^(pool|server) /#&/' /etc/chrony.conf # Arch ships either form
	cat >>/etc/chrony.conf <<'EOF'
server time.cloudflare.com iburst nts
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

	# Non-Mono variant on purpose - Mono clips icons. sans-serif and serif
	# already resolve to Noto Sans and Noto Serif (fontconfig's 60-latin.conf).
	cat >/etc/fonts/local.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
</fontconfig>
EOF

	# pacman output for a human: colour, the package list as a table (name,
	# old → new version, size) instead of one wrapped line, Pac-Man in the
	# progress bar. The mirrorlist is the ISO's, copied by pacstrap: see
	# README, Packages.
	sed -i -e 's/^#Color$/Color/' -e '/^Color$/a ILoveCandy' \
		-e 's/^#VerbosePkgLists$/VerbosePkgLists/' /etc/pacman.conf
	local opt
	for opt in Color ILoveCandy VerbosePkgLists; do
		grep -q "^$opt\$" /etc/pacman.conf || {
			err "pacman.conf: $opt not set."
			exit 1
		}
	done
}

# --- entry -----------------------------------------------------------------

main_live() {
	: >"$LOG_FILE"
	info "Arch install - live ISO phase. Log: $LOG_FILE"

	run_step step_preflight
	run_step step_network
	detect_ucode
	detect_swap_gb
	prompt_inputs # interactive - outside run_step
	derive_parts
	run_step step_partition
	run_step step_luks
	LUKS_UUID="$(blkid -s UUID -o value "$PART_LUKS")"
	run_step step_btrfs
	step_fido2 # interactive - outside run_step
	run_step step_pacstrap
	run_step step_chroot
	run_step step_boot_entries
	run_step step_dotfiles_clone
	step_finish # interactive - outside run_step
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
} # end of partial-download guard
