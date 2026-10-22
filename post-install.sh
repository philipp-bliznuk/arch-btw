#!/usr/bin/env bash
#
# Arch Linux - post-install (first boot). Run as your user from TTY2 (Ctrl-Alt-F2):
#   ~/projects/dotfiles/post-install.sh
#
# TTY1 runs `exec sway` once the dotfiles are linked; TTY2 stays a plain shell.
# Resumable: markers under ~/.local/state/arch-btw/done/<step>.
#
# Flags:  --list          step status
#         --redo <step>   re-run one step
# Debug:  DEBUG=1 post-install.sh

set -Eeuo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES
readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_DIR="$HOME/.local/state/arch-btw"
readonly DONE_DIR="$STATE_DIR/done"
readonly LOG_FILE="$STATE_DIR/post-install.log"
readonly REPO_SSH="git@pb:philipp-bliznuk/arch-btw.git"

readonly STEPS=(
	"bootloader:step_bootloader"
	"network:step_network"
	"nm_connectivity:step_nm_connectivity"
	"snapper:step_snapper"
	"luks_header:step_luks_header"
	"pacman_hooks:step_pacman_hooks"
	"gpu_helper:step_gpu_helper"
	"battery_limit:step_battery_limit"
	"yubikey_pam:step_yubikey_pam"
	"lock_pam:step_lock_pam"
	"lid:step_lid"
	"aur_helper:step_aur_helper"
	"librewolf:step_librewolf"
	"firecfg:step_firecfg"
	"dotfiles:step_dotfiles"
	"theme:step_theme"
	"keys:step_keys"
	"smb:step_smb"
)

# --- helpers ---------------------------------------------------------------

_c() { printf '%s' "$(tput setaf "$1" 2>/dev/null || true)"; }
_r() { printf '%s' "$(tput sgr0 2>/dev/null || true)"; }
info() { printf '%s==>%s %s\n' "$(_c 4)" "$(_r)" "$*"; }
success() { printf '%s==>%s %s\n' "$(_c 2)" "$(_r)" "$*"; }
warn() { printf '%s==>%s %s\n' "$(_c 3)" "$(_r)" "$*" >&2; }
err() { printf '%s==>%s %s\n' "$(_c 1)" "$(_r)" "$*" >&2; }
banner() { printf '\n%s### %s%s\n' "$(_c 6)" "$*" "$(_r)"; }

pause() {
	local msg="${1:-Press Enter to continue}"
	printf '%s>>>%s %s' "$(_c 5)" "$(_r)" "$msg" >/dev/tty
	read -r </dev/tty
}

confirm() {
	local ans
	printf '%s>>>%s %s [y/N] ' "$(_c 5)" "$(_r)" "$1" >/dev/tty
	read -r ans </dev/tty
	[[ "$ans" == [yY] ]]
}

# _ask VAR "Prompt" [default]: Enter keeps the default; without one, asks again.
_ask() {
	local -n _var="$1"
	local _ans=""
	while [[ -z "$_ans" ]]; do
		printf '%s>>>%s %s%s: ' "$(_c 5)" "$(_r)" "$2" "${3:+ [$3]}" >/dev/tty
		read -r _ans </dev/tty
		_ans="${_ans:-${3:-}}"
	done
	_var="$_ans"
}

# Echoes the mountpoint; returns 1 on skip, 2 when the mount fails. Callers
# run it inside $(...) on the left of ||, where set -e is off, so every
# command that matters carries its own || return.
USB_MNT="/mnt/usb"
mount_usb() {
	pause "Insert the USB stick, then press Enter"
	echo "Removable partitions:" >/dev/tty
	local line NAME SIZE FSTYPE LABEL HOTPLUG TYPE
	while IFS= read -r line; do
		eval "$line" # lsblk -P: shell-quoted key="value" pairs
		[[ "$HOTPLUG" == "1" && "$TYPE" == "part" && -n "$FSTYPE" ]] || continue
		printf '  %s  %s  %s  %s\n' "$NAME" "$SIZE" "$FSTYPE" "$LABEL" >/dev/tty
	done < <(lsblk -Ppo NAME,SIZE,FSTYPE,LABEL,HOTPLUG,TYPE)

	local part
	while :; do
		printf 'USB partition (e.g. /dev/sdb1), or "s" to skip: ' >/dev/tty
		read -r part </dev/tty
		[[ "$part" == "s" ]] && return 1
		[[ -b "$part" ]] && break
		err "Not a block device: $part"
	done

	sudo mkdir -p "$USB_MNT" || return 2
	local fstype
	fstype="$(lsblk -no FSTYPE "$part")"
	case "$fstype" in
	vfat | exfat) sudo mount -o "uid=$(id -u),gid=$(id -g)" "$part" "$USB_MNT" || return 2 ;;
	*)
		warn "$fstype stick - files may be unreadable as $USER; prefer FAT/exFAT."
		sudo mount "$part" "$USB_MNT" || return 2
		;;
	esac
	printf '%s\n' "$USB_MNT"
}

umount_usb() {
	sync
	sudo umount "$USB_MNT" 2>/dev/null || true
	success "USB unmounted - safe to remove."
}

is_done() { [[ -f "$DONE_DIR/$1" ]]; }
mark_done() { touch "$DONE_DIR/$1"; }

sudo_keepalive() {
	sudo -v
	(while true; do
		sudo -n true || true # the subshell inherits set -e; yubikey_pam runs sudo -k
		sleep 60
	done 2>/dev/null) &
	KEEPALIVE_PID=$!
	trap 'kill "$KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

CURRENT_STEP=""
run_step() {
	local name="$1" fn="$2"
	CURRENT_STEP="$name"
	banner "$name"
	(
		trap - ERR
		[[ "${DEBUG:-0}" == "1" ]] && set -x
		PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: '
		"$fn"
	) 2>&1 | tee -a "$LOG_FILE"
	return "${PIPESTATUS[0]}"
}

on_error() {
	local ec=$?
	err "FAILED in step: ${CURRENT_STEP:-unknown} (exit $ec)"
	err "Step NOT marked done - fix the cause and re-run to resume here."
	err "Log: $LOG_FILE"
	exit "$ec"
}
trap on_error ERR

# --- steps -----------------------------------------------------------------

step_bootloader() {
	sudo bootctl status || true

	# Stale NVRAM entries = "Linux Boot Manager" entries whose partuuid ≠ the mounted ESP.
	local esp_uuid
	esp_uuid="$(findmnt -no PARTUUID /boot/efi || true)"

	if [[ -n "$esp_uuid" ]]; then
		info "Current ESP partuuid: $esp_uuid"
		local line id part have_current=0
		while IFS= read -r line; do
			id="$(grep -oE 'Boot[0-9A-Fa-f]{4}' <<<"$line" | sed 's/Boot//' || true)"
			part="$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$line" | head -1 || true)"
			[[ -n "$id" && -n "$part" ]] || continue
			if [[ "${part,,}" != "${esp_uuid,,}" ]]; then
				warn "Stale entry $id (partuuid $part):"
				printf '  %s\n' "$line"
				confirm "Delete boot entry $id?" && sudo efibootmgr -b "$id" -B
			else
				have_current=1
			fi
		done < <(sudo efibootmgr -v | grep -iE 'Linux Boot Manager|Fallback' || true)

		if ((! have_current)); then
			warn "No NVRAM entry points at the current ESP - re-running bootctl install."
			sudo bootctl install
		fi
	else
		warn "Could not read the ESP partuuid - inspect \`efibootmgr\` manually."
	fi
}

step_network() {
	if curl -fsSI --max-time 5 https://archlinux.org >/dev/null 2>&1; then
		success "Online."
		return 0
	fi
	warn "Offline - connecting Wi-Fi."
	nmcli device wifi list
	local ssid
	printf 'SSID: ' >/dev/tty
	read -r ssid </dev/tty
	nmcli device wifi connect "$ssid" --ask
}

# NetworkManager re-checks connectivity every 300 s by default; after a router
# outage the shell shows "limited" for minutes although the link is back. 60 s
# keeps the status honest without spamming the check URL.
step_nm_connectivity() {
	sudo mkdir -p /etc/NetworkManager/conf.d
	sudo tee /etc/NetworkManager/conf.d/connectivity.conf >/dev/null <<'EOF'
[connectivity]
interval=60
EOF
	sudo nmcli general reload conf 2>/dev/null || true
}

step_snapper() {
	if sudo snapper list-configs | grep -qE '^root\s'; then
		success "snapper root config exists."
	else
		# A failed umount must stop here: rm -rf on a mounted @snapshots would
		# walk into the snapshot tree.
		! mountpoint -q /.snapshots || sudo umount /.snapshots
		sudo rm -rf /.snapshots
		sudo snapper -c root create-config /
		sudo btrfs subvolume delete /.snapshots || true
		sudo mkdir /.snapshots
		sudo mount -a
		sudo chmod 750 /.snapshots
	fi
	# snap-pac pre/post pairs use the number cleanup (snap-restore picks the
	# newest pre); the template keeps 50 of those and 10 monthly plus 10 yearly
	# timeline snapshots of root
	sudo snapper -c root set-config \
		TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
		TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
		NUMBER_LIMIT=20

	if sudo snapper list-configs | grep -qE '^home\s'; then
		success "snapper home config exists."
	else
		sudo snapper -c home create-config /home
	fi
	sudo snapper -c home set-config \
		TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
		TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
}

step_luks_header() {
	# The device under the installer's mapping, not the first LUKS device lsblk
	# lists (a second disk or an encrypted stick would sort first). -l: the
	# tree form prefixes the parent with box-drawing glyphs.
	local luks
	luks="$(lsblk -slpno NAME /dev/mapper/cryptroot 2>/dev/null | sed -n 2p || true)"
	[[ -b "$luks" ]] || {
		err "No LUKS device under /dev/mapper/cryptroot."
		return 1
	}
	info "LUKS partition: $luks"

	local dest rc=0
	dest="$(mount_usb)" || rc=$?
	case "$rc" in
	0) ;;
	1)
		warn "Skipped - back up the LUKS header later."
		return 0
		;;
	*)
		err "USB mount failed - fix the stick, then: post-install.sh --redo luks_header"
		return 1
		;;
	esac

	# Never to ~ - @home snapshots would keep a copy. Minutes in the name: a
	# second backup the same day (--redo after a keyslot change) must not fail
	# on the existing file, luksHeaderBackup refuses to overwrite.
	sudo cryptsetup luksHeaderBackup "$luks" \
		--header-backup-file "$dest/luks-header-$(date +%Y%m%d-%H%M).img"
	success "Header written. Re-take after any keyslot change."
	umount_usb
}

# Flag /run/reboot-required (tmpfs → cleared by the reboot itself) after
# packages that need one. The shell watches the file (kernel-modules-hook keeps
# the running kernel's modules in place, so their absence is no signal).
# /run/qs-apps-changed is touched whenever a .desktop file is installed or
# removed so the launcher re-reads the app list (bin/qs-apps). Orphans are
# listed after every transaction: nothing else ever mentions them. Pending
# .pacnew files go to /var/lib/pacnew-pending (not /run: they outlive a
# reboot) after any transaction touching /etc; the launcher's Packages rows
# show them and qs-pkg pacdiff rewrites the file after a merge session.
# (pacdiff -p knows the backup files of installed packages only, so a .pacsave
# left by a removed package never shows; qs-pkg remove uses -Rns, no .pacsave.)
step_pacman_hooks() {
	sudo mkdir -p /etc/pacman.d/hooks
	sudo tee /etc/pacman.d/hooks/zz-reboot-required.hook >/dev/null <<'EOF'
[Trigger]
Operation = Upgrade
Operation = Install
Type = Package
Target = linux
Target = linux-lts
Target = systemd
Target = glibc
Target = dbus
Target = dbus-broker
Target = linux-firmware
Target = amd-ucode
Target = intel-ucode
Target = mesa
Target = cryptsetup
Target = btrfs-progs

[Action]
Description = Flagging reboot-required...
When = PostTransaction
NeedsTargets
Exec = /bin/sh -c 'cat >> /run/reboot-required'
EOF
	sudo tee /etc/pacman.d/hooks/zz-qs-apps.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/share/applications/*.desktop

[Action]
Description = Flagging launcher app list refresh...
When = PostTransaction
Exec = /bin/sh -c 'date +%s > /run/qs-apps-changed'
EOF
	sudo tee /etc/pacman.d/hooks/zz-orphans.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Checking for orphaned packages...
When = PostTransaction
Exec = /bin/sh -c 'o=$(pacman -Qdtq) || exit 0; echo "orphans (pacman -Rns): $(echo $o)"'
EOF
	sudo tee /etc/pacman.d/hooks/zz-pacnew.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = etc/*

[Action]
Description = Listing pacnew files...
Depends = pacman-contrib
When = PostTransaction
Exec = /bin/sh -c 'f=/var/lib/pacnew-pending; pacdiff -o | tee "$f"; [ -s "$f" ] || rm -f "$f"'
EOF
}

# Intel GPU busy % needs the i915 PMU → CAP_PERFMON. Build the tiny helper
# from bin/src, install root-owned (a user-writable file would lose the cap).
step_gpu_helper() {
	[[ -d /sys/bus/event_source/devices/i915 ]] || {
		info "No i915 PMU (not an Intel GPU) - Metrics falls back to sysfs."
		return 0
	}
	local src="$DOTFILES/bin/src/qs-gpu-busy.c" tmp
	tmp="$(mktemp)"
	gcc -O2 -Wall -o "$tmp" "$src"
	sudo install -o root -g root -m 755 "$tmp" /usr/local/bin/qs-gpu-busy
	sudo setcap cap_perfmon=ep /usr/local/bin/qs-gpu-busy
	rm -f "$tmp"
}

# Charge limit 75→80 % through UPower (persists in its own state; no TLP).
# Lithium cells age fastest sitting full; the Battery popup can flip it (`c`).
step_battery_limit() {
	local out
	out="$("$DOTFILES/bin/qs-battery" status)"
	[[ "$out" == *'"supported":true'* ]] || {
		info "Battery charge thresholds not supported - skipping."
		return 0
	}
	"$DOTFILES/bin/qs-battery" limit on
}

# pam_u2f ahead of the password for login, sudo and polkit. Not in system-auth:
# that stack also serves sshd (and su has its own), where "sufficient" would
# log in anyone holding a plugged key. The lock screen has its own services
# (lock_pam). The cue names the way out: while the token waits for a touch the
# tty still echoes, so a password typed then shows in clear and is discarded.
step_yubikey_pam() {
	local tmp
	tmp="$(mktemp)"
	pause "Insert YubiKey #1, then Enter (asks FIDO2 PIN once + touch)"
	pamu2fcfg -o pam://arch-yubikey -i pam://arch-yubikey >"$tmp"
	pause "Now swap to YubiKey #2, then Enter"
	pamu2fcfg -n -o pam://arch-yubikey -i pam://arch-yubikey >>"$tmp"

	# group-readable: the Quickshell lock screen runs pam_u2f as the user
	sudo install -o root -g "$(id -gn)" -m 640 "$tmp" /etc/u2f_mappings
	rm -f "$tmp"

	local rule='auth sufficient pam_u2f.so authfile=/etc/u2f_mappings cue [cue_prompt=Touch the YubiKey, or unplug it and type the password] origin=pam://arch-yubikey appid=pam://arch-yubikey'
	# sudo and login: the packages' own files, rule above their `auth include`
	# line (login: after pam_nologin; pacnew on upgrade, pacdiff keeps it)
	local f
	for f in sudo login; do
		sudo sed -i -e '/pam_u2f\.so/d' \
			-e "0,/^auth[[:space:]]\+include/s|^auth[[:space:]]\+include|${rule}\n&|" "/etc/pam.d/$f"
		grep -q '^auth sufficient pam_u2f\.so' "/etc/pam.d/$f" || {
			err "/etc/pam.d/$f: no auth include line to put pam_u2f above; file layout changed."
			return 1
		}
	done
	# polkit-1: vendor file in /usr/lib/pam.d, an /etc copy takes precedence
	[[ -r /usr/lib/pam.d/polkit-1 ]] || {
		err "missing /usr/lib/pam.d/polkit-1 (polkit moved its PAM file; adjust this step)"
		return 1
	}
	{
		printf '#%%PAM-1.0\n# Written by post-install.sh (yubikey_pam): /usr/lib/pam.d/polkit-1 plus pam_u2f.\n%s\n' "$rule"
		grep -vE '^\s*(#|$)' /usr/lib/pam.d/polkit-1
	} | sudo install -o root -g root -m 644 /dev/stdin /etc/pam.d/polkit-1

	info "Testing (touch a key):"
	sudo -k
	sudo true && success "sudo works." || warn "Test failed - password still works; verify /etc/pam.d/sudo before logging out."
}

# PAM services for the Quickshell lock screen (quickshell/lock/Locker.qml).
# Password: system-auth's unix stack without pam_systemd_home (no homed here)
# and without nullok. YubiKey: pam_u2f alone, presence only (no PIN), on a
# second PAM context that waits for a touch while the password field is live.
# pam_faillock keeps its tally in /run/faillock/$USER inside a root-only dir;
# the lock screen runs PAM as the user and cannot create that file, so a
# tmpfiles rule creates it at boot (same owner and mode pam_faillock uses).
step_lock_pam() {
	sudo install -o root -g root -m 644 /dev/stdin /etc/pam.d/qs-lock-password <<-'EOF'
		#%PAM-1.0
		# Quickshell lock screen, password. Written by post-install.sh (lock_pam).
		auth       required                    pam_faillock.so  preauth
		auth       [success=1 default=bad]     pam_unix.so      try_first_pass
		auth       [default=die]               pam_faillock.so  authfail
		auth       optional                    pam_permit.so
		auth       required                    pam_env.so
		auth       required                    pam_faillock.so  authsucc
		# inert: quickshell's PamContext only calls pam_authenticate
		account    include                     system-auth
	EOF
	sudo install -o root -g root -m 644 /dev/stdin /etc/pam.d/qs-lock-u2f <<-'EOF'
		#%PAM-1.0
		# Quickshell lock screen, YubiKey touch. Written by post-install.sh (lock_pam).
		auth       required   pam_u2f.so  authfile=/etc/u2f_mappings cue origin=pam://arch-yubikey appid=pam://arch-yubikey
		# inert: quickshell's PamContext only calls pam_authenticate
		account    include    system-auth
	EOF
	sudo install -o root -g root -m 644 /dev/stdin /etc/tmpfiles.d/qs-faillock.conf <<-EOF
		# Written by post-install.sh (lock_pam): faillock tally the user-run lock screen can update.
		f /run/faillock/$(id -un) 0660 $(id -un) root -
	EOF
	sudo systemd-tmpfiles --create /etc/tmpfiles.d/qs-faillock.conf
	success "PAM services qs-lock-password and qs-lock-u2f written, faillock tally file created."
}

# Lid and power key. logind owns the lid: shut and undocked it suspends, then
# hibernates (HibernateDelaySec=1h, install.sh), on battery and on AC alike;
# swayidle's before-sleep locks on the way down. Docked (an external display
# connected and enabled, or a dock reporting its switch) it does nothing but
# sway folds the panel away (sway/config bindswitch) and the idle ladder alone
# applies; logind re-checks that after every event while the lid stays shut,
# so undocking a shut laptop sleeps it. The power key does what the lid does
# (logind's default is poweroff, sway binds nothing, so one accidental press
# ended the session); a 5 s hold powers off cleanly, the way out of a hung
# session (logind's default: ignore).
step_lid() {
	sudo install -D -o root -g root -m 644 /dev/stdin /etc/systemd/logind.conf.d/00-lid.conf <<-'EOF'
		# Written by post-install.sh (lid).
		[Login]
		# undocked: sleep at once; docked (external display up): nothing
		HandleLidSwitch=suspend-then-hibernate
		HandleLidSwitchDocked=ignore
		HandlePowerKey=suspend-then-hibernate
		HandlePowerKeyLongPress=poweroff
	EOF
	sudo systemctl reload systemd-logind
	success "Lid and power key policy written (00-lid.conf), logind reloaded."
}

# yay for AUR-only desktop apps (slack-desktop, zoom). yay-bin: no Go toolchain.
# Built via bin/yay-git so the GitHub mirror covers AUR outages. makepkg's
# default OPTIONS has debug on, which splits a -debug package out of every
# build and makepkg -si installs it; off system-wide before the first build.
# The same drop-in lets a build use every core (stock MAKEFLAGS is unset, one
# job) and keeps src, pkg and the finished package on the /tmp tmpfs: nothing
# touches the disk, the package is installed from there and gone by the next
# boot (tmpfiles: 10 days). A build bigger than the tmpfs (half of RAM) fails
# there; a batch of the four -bin packages peaks around 4 GB. The package has
# to leave ~/.cache/yay because yay's cleanAfter (yay/config.json) deletes
# downloaded sources only and keeps every *.pkg.* file; makepkg creates the
# directory. No compression: the file is read once by pacman -U.
step_aur_helper() {
	sudo install -D -o root -g root -m 644 /dev/stdin /etc/makepkg.conf.d/local.conf <<-'EOF'
		# Written by post-install.sh (aur_helper). Local builds: no -debug split
		# packages, all cores, src/pkg and the package on tmpfs, uncompressed.
		OPTIONS+=(!debug)
		MAKEFLAGS="-j$(nproc)"
		BUILDDIR=/tmp/makepkg
		PKGDEST=/tmp/makepkg
		PKGEXT='.pkg.tar'
	EOF
	if pacman -Q yay >/dev/null 2>&1; then
		echo "yay already installed"
		return 0
	fi
	"$DOTFILES/bin/yay-git" yay-bin
}

# LibreWolf ≥ 156 keeps its profile in $XDG_CONFIG_HOME/librewolf/librewolf,
# but the firejail 0.9.80 profile only whitelists legacy ~/.librewolf → the
# profile landed on the sandbox tmpfs and was lost every launch. Whitelist the
# XDG dir and put the overrides where prefcalls.js actually reads them:
# $XDG_CONFIG_HOME/librewolf/librewolf/librewolf.overrides.cfg (yes, twice).
step_librewolf() {
	local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/librewolf/librewolf"
	sudo tee /etc/firejail/librewolf.local >/dev/null <<'EOF'
# XDG profile dir (firejail's stock profile predates LibreWolf's move)
noblacklist ${HOME}/.config/librewolf
mkdir ${HOME}/.config/librewolf
whitelist ${HOME}/.config/librewolf
# Upstream turned AppArmor off for the browser (ignore apparmor further down in
# librewolf.profile); this file is included before that line, so the
# firejail-default profile applies again.
apparmor
# firefox-common.profile adds nou2f (browser-disable-u2f defaults to yes in
# firejail.config), which hides /dev/hidraw*: no WebAuthn with the YubiKey.
# private-dev stays, so the jail still sees only the devices it needs.
ignore nou2f
# Session bus, filtered by xdg-dbus-proxy (the stock profile talks to the
# portal Documents service only): the MPRIS name for the bar's media widget,
# and the desktop portal, Firefox's route to the colour scheme and to screen
# capture on Wayland. xdg-desktop-portal/sway-portals.conf (dotfiles) turns
# the portal's DynamicLauncher off: through it a host app rewrites any
# ~/.local/share/applications/*.desktop without a dialog.
dbus-user.own org.mpris.MediaPlayer2.firefox.*
dbus-user.talk org.freedesktop.portal.Desktop
EOF
	mkdir -p "$cfg" "$HOME/.librewolf"
	cat >"$cfg/librewolf.overrides.cfg" <<'EOF'
// librewolf.cfg upgrades private network addresses to HTTPS as well (loopback
// is always exempt); homelab services speak plain HTTP, so IP literals in
// private and link-local ranges load as typed (Firefox's default). The
// internet is still HTTPS-Only. A per-site exception would cover one host at
// a time; several services on several ports made the global switch cheaper.
// Cost: on a hostile LAN a typed http://10.x or http://192.168.x URL is not
// upgraded; https:// URLs are unaffected.
defaultPref("dom.security.https_only_mode.upgrade_local", false);
defaultPref("network.http.referer.XOriginPolicy", 2);
defaultPref("media.autoplay.blocking_policy", 2);
defaultPref("librewolf.webgl.prompt.hide", false);
// Hardware video decode via VA-API (intel-media-driver / libva-mesa-driver).
// AV1 off: pre-Tiger-Lake iGPUs lack an AV1 decoder, and sites pick AV1 when
// offered → software decode. Disabling it makes them serve VP9/H.264 instead.
defaultPref("media.ffmpeg.vaapi.enabled", true);
defaultPref("media.hardware-video-decoding.force-enabled", true);
defaultPref("media.av1.enabled", false);
// Extension base CSP: no remote script or plugin in extension pages (Firefox's
// MV3 default, applied to MV2 extensions too). default-src 'none' on top would
// also block connect-src, i.e. uBlock Origin's filter-list updates.
defaultPref("extensions.webextensions.base-content-security-policy",
            "script-src 'self' 'wasm-unsafe-eval'; object-src 'self';");
EOF
	ln -sfn "$cfg/librewolf.overrides.cfg" "$HOME/.librewolf/librewolf.overrides.cfg"
	success "librewolf.overrides.cfg written to $cfg (legacy ~/.librewolf symlinked)."
}

step_firecfg() {
	# symlinks in /usr/local/bin for the installed programs named in
	# /etc/firejail/firecfg.config (librewolf, ssh, man, ping, ffplay, pdftotext,
	# ...; see `firecfg --list`). Programs with a profile but outside that list
	# (curl, git, nvim, tmux, node) run unconfined. Add or remove names in
	# /etc/firejail/firecfg.d/*.conf (`!name` removes), never in firecfg.config.
	# The hook re-runs it after every transaction that touches /usr/bin, so AUR
	# packages installed later (slack, zoom) get their symlink and fixed .desktop.
	sudo tee /etc/pacman.d/hooks/firecfg.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/bin/*

[Action]
Description = Refreshing firejail symlinks (firecfg)...
Depends = firejail
When = PostTransaction
Exec = /usr/bin/firecfg
EOF
	sudo firecfg
}

# Replaces a symlink or nothing. A real file or directory at $dest is the
# user's (a ~/.local/bin full of shims, a config dir an app wrote first):
# the step stops and names it instead of deleting it.
link() {
	local src="$1" dest="$2"
	[[ -e "$src" ]] || {
		err "missing: $src"
		return 1
	}
	if [[ -e "$dest" && ! -L "$dest" ]]; then
		err "not a symlink, move it away first: $dest"
		return 1
	fi
	rm -f "$dest"
	mkdir -p "$(dirname "$dest")"
	ln -sf "$src" "$dest"
	info "$dest -> $src"
}

step_dotfiles() {
	local pkg
	for pkg in bat fastfetch git kitty nvim qt6ct quickshell ruff sway tmux wallpapers xdg-desktop-portal yay yazi zsh; do
		link "$DOTFILES/$pkg" "$XDG_CONFIG_HOME/$pkg"
	done
	link "$DOTFILES/gtk" "$XDG_CONFIG_HOME/gtk-3.0" # same gtk.css + settings.ini for GTK 3 and 4
	link "$DOTFILES/gtk" "$XDG_CONFIG_HOME/gtk-4.0"
	link "$DOTFILES/jj/config.toml" "$XDG_CONFIG_HOME/jj/config.toml"
	link "$DOTFILES/containers/containers.conf" "$XDG_CONFIG_HOME/containers/containers.conf"
	link "$DOTFILES/containers/registries.conf" "$XDG_CONFIG_HOME/containers/registries.conf"
	link "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv" # only file in $HOME; bootstraps ZDOTDIR
	link "$DOTFILES/bin" "$HOME/.local/bin"      # qs-* helper scripts (sway binds + Quickshell call them)
	local entry
	for entry in "$DOTFILES"/applications/*.desktop; do # nvim and yazi wrapped in kitty: usable as xdg-open defaults
		link "$entry" "$HOME/.local/share/applications/${entry##*/}"
	done
	# GIO reads a user-dir entry's types from the user dir's cache (bin/qs-defaults
	# refreshes it too); pacman's hook only covers /usr/share.
	update-desktop-database "$HOME/.local/share/applications"
	mkdir -p "$HOME/.local/state/qs/toggles"

	rm -f "$HOME/.zshrc" # install-time placeholder
	# xdg-user-dirs 0.19+ defaults PROJECTS to ~/Projects; repos live in
	# ~/projects (install.sh clones there), so register that and drop the stray.
	xdg-user-dirs-update --set PROJECTS "$HOME/projects"
	xdg-user-dirs-update
	[[ -d "$HOME/Projects" ]] && rmdir --ignore-fail-on-non-empty "$HOME/Projects"
	success "Dotfiles linked."
}

# GTK 3 on Wayland reads org.gnome.desktop.interface from dconf when the schema
# exists and ignores settings.ini for those keys; libadwaita and the settings
# portal (dark mode for Electron apps, LibreWolf) read color-scheme from the
# same place. Needs the user D-Bus socket, present on any systemd login.
step_theme() {
	local iface=org.gnome.desktop.interface
	gsettings set "$iface" gtk-theme adw-gtk3-dark
	gsettings set "$iface" color-scheme prefer-dark
	gsettings set "$iface" font-name 'Adwaita Sans 10'
	gsettings set "$iface" monospace-font-name 'JetBrainsMono Nerd Font Mono 10'
	gsettings set "$iface" icon-theme Adwaita
	gsettings set "$iface" cursor-theme Adwaita
	success "GTK theme set (adw-gtk3-dark, prefer-dark); Qt follows via QT_QPA_PLATFORMTHEME=qt6ct from .zprofile."
}

# gpg-agent runs from gnupg's static user sockets (gpg-agent.socket,
# gpg-agent-ssh.socket: wanted by sockets.target, nothing to enable), under the
# systemd user environment qs-session imports (WAYLAND_DISPLAY, qt6ct → pinentry-qt).
# USB layout:
#   keys/gpg/ic/public.asc                        YubiKey identity, public only
#   keys/gpg/{pb,gx}/{public,secret-keys}.asc     on-disk identities
#   keys/ssh/id_ed25519_{pb,gx}[.pub]
_keys_import() {
	local usb="$1" id pub sec k
	for id in pb ic gx; do
		pub="$usb/keys/gpg/$id/public.asc"
		if [[ -f "$pub" ]]; then
			gpg --import "$pub"
			gpg --with-colons --show-keys "$pub" | # primary fpr only
				awk -F: '/^fpr:/{print $10":6:"; exit}' | gpg --import-ownertrust
			success "Imported public key: $id"
		else
			warn "No public key for $id at $pub"
		fi
		sec="$usb/keys/gpg/$id/secret-keys.asc"
		if [[ -f "$sec" ]]; then
			gpg --import "$sec" # prompts passphrase
			success "Imported secret key: $id"
		fi
	done

	for k in id_ed25519_pb id_ed25519_gx; do
		if [[ -f "$usb/keys/ssh/$k" ]]; then
			install -m 600 "$usb/keys/ssh/$k" "$HOME/.ssh/$k"
			[[ -f "$usb/keys/ssh/$k.pub" ]] && install -m 644 "$usb/keys/ssh/$k.pub" "$HOME/.ssh/$k.pub"
			success "Installed SSH key: $k"
		else
			warn "No SSH key at $usb/keys/ssh/$k"
		fi
	done
}

step_keys() {
	sudo systemctl enable --now pcscd.socket
	GPG_TTY="$(tty)"
	export GPG_TTY # pinentry-qt falls back to curses here, needs the tty

	mkdir -p "$HOME/.gnupg"
	chmod 700 "$HOME/.gnupg"
	cat >"$HOME/.gnupg/scdaemon.conf" <<'EOF'
disable-ccid
pcsc-shared
EOF
	cat >"$HOME/.gnupg/gpg-agent.conf" <<'EOF'
pinentry-program /usr/bin/pinentry-qt
enable-ssh-support
default-cache-ttl 604800
max-cache-ttl 604800
EOF
	gpgconf --kill gpg-agent # pick up new config before imports

	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	# "s" at the USB prompt skips the import only; the card export, ~/.ssh/config
	# and the remote still happen, a later --redo keys picks the import up.
	local usb rc=0
	usb="$(mount_usb)" || rc=$?
	case "$rc" in
	0)
		_keys_import "$usb"
		umount_usb
		;;
	1) warn "Skipped key import - later: post-install.sh --redo keys" ;;
	*)
		err "USB mount failed - fix the stick, then: post-install.sh --redo keys"
		return 1
		;;
	esac

	pause "Insert a YubiKey, then Enter"
	gpg --card-status || warn "Card not seen - check pcscd / scdaemon.conf."

	SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
	export SSH_AUTH_SOCK
	gpg-connect-agent updatestartuptty /bye >/dev/null || true

	ssh-add -L 2>/dev/null | grep -i 'cardno:' >"$HOME/.ssh/id_ed25519_ic_yubikey.pub" || true
	if [[ -s "$HOME/.ssh/id_ed25519_ic_yubikey.pub" ]]; then
		chmod 644 "$HOME/.ssh/id_ed25519_ic_yubikey.pub"
		success "Exported YubiKey SSH public key."
	else
		warn "No card SSH key - later: ssh-add -L | grep cardno: > ~/.ssh/id_ed25519_ic_yubikey.pub"
	fi

	cat >"$HOME/.ssh/config" <<'EOF'
Host pb
	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_pb
	IdentitiesOnly yes

Host ic
	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_ic_yubikey.pub
	IdentitiesOnly yes

Host gx
	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_gx
	IdentitiesOnly yes
EOF
	chmod 600 "$HOME/.ssh/config"
	success "Wrote ~/.ssh/config (pb / ic / gx)."

	git -C "$DOTFILES" remote set-url origin "$REPO_SSH" || true
	success "Keys wired."
}

# One SMB share as a pair of systemd units, mounted on first access and
# unmounted after five idle minutes: boot and login never wait for the NAS,
# sleep finds nothing mounted, the next cd remounts, and while something holds
# it open the kernel cifs client reconnects by itself (soft is its default).
# Native units, not fstab x-systemd.* options: the generator would write the
# same two units to /run from a longer line. The password lives in
# /etc/credstore (0600 root) and reaches mount.cifs through LoadCredential=,
# so neither the unit file nor a process list carries it; in this script it
# is expanded only inside a heredoc body and tested as ${pass:+x}, the two
# forms a DEBUG=1 trace does not print. LAN names do not resolve on this box
# (resolved sends every name to Quad9), hence the IP. Four tries; port 445 is
# probed first so a typo gets a plain message instead of the mount journal.
# Another --redo smb adds a second share or, on the same path, replaces one.
step_smb() {
	confirm "Mount an SMB share (NAS)?" || {
		info "Skipped - post-install.sh --redo smb adds one later."
		return 0
	}
	sudo pacman -S --needed --noconfirm cifs-utils
	local host="" share="" user="$USER" target="$HOME/nas" pass
	local unit="" cred="" new since try
	for try in 1 2 3 4; do
		_ask host "NAS host (IP)" "$host"
		while :; do
			_ask share "Share (exported name, not a path)" "$share"
			while [[ "$share" == /* ]]; do share="${share#/}"; done
			[[ -n "$share" ]] && break
		done
		_ask user "User" "$user"
		pass=""
		while [[ -z "${pass:+x}" ]]; do
			printf '%s>>>%s Password: ' "$(_c 5)" "$(_r)" >/dev/tty
			IFS= read -rs pass </dev/tty
			printf '\n' >/dev/tty
		done
		while :; do
			_ask target "Mount path" "$target"
			target="${target/#\~\//$HOME/}"
			while [[ "$target" == */ ]]; do target="${target%/}"; done
			[[ "$target" == /?* && "$target" != "$HOME" ]] && break
			warn "Mount path must be absolute, neither / nor $HOME."
		done
		if ! timeout 3 bash -c "exec 3<>/dev/tcp/\$1/445" _ "$host" 2>/dev/null; then
			warn "Nothing answers on $host:445."
			continue
		fi
		new="$(systemd-escape -p "$target")"
		[[ -z "$unit" || "$unit" == "$new" ]] || _smb_remove "$unit" "$cred"
		unit="$new"
		cred="smb-${unit//\\/}" # a - in the path escapes to \x2d; LoadCredential= would drop the backslash
		sudo install -D -o root -g root -m 600 /dev/stdin "/etc/credstore/$cred" <<-EOF
			username=$user
			password=$pass
		EOF
		_smb_units "$unit" "$cred" "//$host/$share" "$target"
		mkdir -p "$target" 2>/dev/null || sudo mkdir -p "$target"
		sudo systemctl daemon-reload
		sudo systemctl enable "$unit.automount"
		sudo systemctl stop "$unit.mount" 2>/dev/null || true # a --redo must not pass on the old session
		since=$(date +%s)
		sudo systemctl restart "$unit.automount"
		ls "$target" >/dev/null 2>&1 || true # triggers the mount; the proof is findmnt
		if findmnt -t cifs -n "$target" >/dev/null; then
			success "Mounted $(findmnt -t cifs -no SOURCE "$target") on $target."
			return 0
		fi
		warn "Mount failed (try $try of 4):"
		sudo journalctl -u "$unit.mount" --since "@$since" -o cat --no-pager 2>/dev/null |
			grep -v 'Refer to the\|Mount process exited\|Failed with result' >&2 || true
	done
	[[ -z "$unit" ]] || _smb_remove "$unit" "$cred"
	err "Giving up after four tries - post-install.sh --redo smb"
	return 1
}

# _smb_units UNIT CRED WHAT WHERE: the mount and the automount that triggers it.
_smb_units() {
	local unit="$1" cred="$2" what="$3" where="$4"
	sudo install -D -o root -g root -m 644 /dev/stdin "/etc/systemd/system/$unit.mount" <<-EOF
		# Written by post-install.sh (smb).
		[Unit]
		Description=$what

		[Mount]
		What=$what
		Where=$where
		Type=cifs
		# echo_interval: a held-open share whose NAS went silent blocks the shell
		# for 3 intervals before soft returns an error, 187 s at the default 60
		Options=credentials=%d/$cred,uid=$(id -u),gid=$(id -g),file_mode=0644,dir_mode=0755,echo_interval=15
		LoadCredential=$cred
		# shutdown with the NAS gone: detach instead of waiting on it
		LazyUnmount=yes
	EOF
	sudo install -D -o root -g root -m 644 /dev/stdin "/etc/systemd/system/$unit.automount" <<-EOF
		# Written by post-install.sh (smb).
		[Unit]
		Description=$what on demand

		[Automount]
		Where=$where
		TimeoutIdleSec=300

		[Install]
		WantedBy=multi-user.target
	EOF
}

# _smb_remove UNIT CRED: unit pair and credential, after a path change mid-step
# or the last failed try. Automount first, so nothing re-triggers the mount.
_smb_remove() {
	sudo systemctl disable --now "$1.automount" 2>/dev/null || true
	sudo systemctl stop "$1.mount" 2>/dev/null || true
	sudo rm -f "/etc/systemd/system/$1.mount" "/etc/systemd/system/$1.automount" "/etc/credstore/$2"
	sudo systemctl daemon-reload
	sudo systemctl reset-failed "$1.mount" 2>/dev/null || true
}

do_list() {
	local entry name
	for entry in "${STEPS[@]}"; do
		name="${entry%%:*}"
		if is_done "$name"; then printf '  [x] %s\n' "$name"; else printf '  [ ] %s\n' "$name"; fi
	done
}

# --- entry -----------------------------------------------------------------

main() {
	mkdir -p "$DONE_DIR"
	: >>"$LOG_FILE"
	sudo_keepalive

	local entry name fn
	for entry in "${STEPS[@]}"; do
		name="${entry%%:*}"
		fn="${entry##*:}"
		if is_done "$name"; then
			info "skip $name (done)"
			continue
		fi
		run_step "$name" "$fn"
		mark_done "$name"
	done
	banner "Done"
	cat <<'EOF'

  Reboot → unlock LUKS (FIDO2 PIN + touch) → TTY1: touch the key, or unplug it and type the password → Sway.
  Re-run a step:  post-install.sh --redo <step>

EOF
}

redo_one() {
	local target="$1" entry name fn
	for entry in "${STEPS[@]}"; do
		name="${entry%%:*}"
		fn="${entry##*:}"
		if [[ "$name" == "$target" ]]; then
			mkdir -p "$DONE_DIR"
			: >>"$LOG_FILE"
			sudo_keepalive
			rm -f "$DONE_DIR/$name"
			run_step "$name" "$fn"
			mark_done "$name"
			return 0
		fi
	done
	err "Unknown step: $target (see --list)"
	exit 1
}

case "${1:-}" in
--list) do_list ;;
--redo)
	[[ -n "${2:-}" ]] || {
		err "--redo needs a step name"
		exit 1
	}
	redo_one "$2"
	;;
"") main ;;
*)
	err "Unknown argument: $1"
	exit 1
	;;
esac
