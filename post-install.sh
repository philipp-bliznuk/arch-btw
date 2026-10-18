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
	"finish:step_finish"
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

# Echoes the mountpoint; returns 1 on skip.
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

	sudo mkdir -p "$USB_MNT"
	local fstype
	fstype="$(lsblk -no FSTYPE "$part")"
	case "$fstype" in
	vfat | exfat) sudo mount -o "uid=$(id -u),gid=$(id -g)" "$part" "$USB_MNT" ;;
	*)
		warn "$fstype stick - files may be unreadable as $USER; prefer FAT/exFAT."
		sudo mount "$part" "$USB_MNT"
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
		sudo -n true
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
		sudo umount /.snapshots || true
		sudo rm -rf /.snapshots
		sudo snapper -c root create-config /
		sudo btrfs subvolume delete /.snapshots || true
		sudo mkdir /.snapshots
		sudo mount -a
		sudo chmod 750 /.snapshots
	fi
	# snap-pac pre/post pairs use the number cleanup (snap-restore picks the
	# newest pre); the Arch defaults also keep 10 yearly timeline snapshots of root
	sudo snapper -c root set-config \
		TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
		TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
		NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10

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
	local luks
	luks="$(lsblk -rno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print "/dev/"$1; exit}')"
	[[ -n "$luks" ]] || {
		err "No crypto_LUKS partition found."
		return 1
	}
	info "LUKS partition: $luks"

	local dest
	dest="$(mount_usb)" || {
		warn "Skipped - back up the LUKS header later."
		return 0
	}

	# Never to ~ - @home snapshots would keep a copy.
	sudo cryptsetup luksHeaderBackup "$luks" \
		--header-backup-file "$dest/luks-header-$(date +%Y%m%d).img"
	success "Header written. Re-take after any keyslot change."
	umount_usb
}

# Flag /run/reboot-required (tmpfs → cleared by the reboot itself) after
# packages that need one. The shell watches the file; kernels are also checked
# once at startup (/usr/lib/modules/$(uname -r) vanishes on upgrade).
# /run/qs-apps-changed is touched whenever a .desktop file is installed or
# removed so the launcher re-reads the app list (bin/qs-apps).
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
	# older revisions put the rule in system-auth (every login); no-op on a fresh install
	sudo sed -i '/pam_u2f\.so/d' /etc/pam.d/system-auth
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

# Lid policy. Closing the lid suspends, then hibernates, on battery and on AC
# alike. With an external display attached logind counts the laptop as docked,
# and then the lid only locks: swayidle relays logind's Lock signal to qs-lock.
step_lid() {
	sudo install -D -o root -g root -m 644 /dev/stdin /etc/systemd/logind.conf.d/00-lid.conf <<-'EOF'
		# Written by post-install.sh (lid).
		[Login]
		HandleLidSwitch=suspend-then-hibernate
		HandleLidSwitchExternalPower=suspend-then-hibernate
		# external display attached: lock only (swayidle relays the Lock signal to qs-lock)
		HandleLidSwitchDocked=lock
	EOF
	sudo systemctl reload systemd-logind
	success "Lid policy written (00-lid.conf), logind reloaded."
}

# yay for AUR-only desktop apps (slack-desktop, zoom). yay-bin: no Go toolchain.
# Built via bin/yay-git so the GitHub mirror covers AUR outages. makepkg's
# default OPTIONS has debug on, which splits a -debug package out of every
# build and makepkg -si installs it; off system-wide before the first build.
step_aur_helper() {
	sudo install -D -o root -g root -m 644 /dev/stdin /etc/makepkg.conf.d/nodebug.conf <<-'EOF'
		# Written by post-install.sh (aur_helper): no -debug split packages from local builds.
		OPTIONS+=(!debug)
	EOF
	rustup default stable # the rustup package ships only proxies; local builds need a toolchain
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
	sudo tee /etc/firejail/librewolf.local >/dev/null <<EOF
# XDG profile dir (firejail's stock profile predates LibreWolf's move)
noblacklist \${HOME}/.config/librewolf
mkdir \${HOME}/.config/librewolf
whitelist \${HOME}/.config/librewolf
# Upstream turned AppArmor off for the browser (ignore apparmor further down in
# librewolf.profile); this file is included before that line, so the
# firejail-default profile applies again.
apparmor
# Session bus, filtered by xdg-dbus-proxy (the stock profile talks to the
# portal Documents service only): the MPRIS name for the bar's media widget,
# and the desktop portal, Firefox's route to the colour scheme and to screen
# capture on Wayland.
dbus-user.own org.mpris.MediaPlayer2.firefox.*
dbus-user.talk org.freedesktop.portal.Desktop
EOF
	mkdir -p "$cfg" "$HOME/.librewolf"
	cat >"$cfg/librewolf.overrides.cfg" <<'EOF'
defaultPref("privacy.resistFingerprinting.letterboxing", true);
defaultPref("network.http.referer.XOriginPolicy", 2);
defaultPref("media.autoplay.blocking_policy", 2);
defaultPref("librewolf.webgl.prompt", true);
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
	# symlinks in /usr/local/bin for every installed program firejail has a
	# profile for (librewolf, ssh, man, ping, ffplay, pdftotext, ...; see
	# `firecfg --list`). Blacklist misbehaving tools in /etc/firejail/firecfg.config.
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
When = PostTransaction
Exec = /usr/bin/firecfg
EOF
	sudo firecfg
}

link() {
	local src="$1" dest="$2"
	[[ -e "$src" ]] || {
		err "missing: $src"
		return 1
	}
	rm -rf "$dest"
	mkdir -p "$(dirname "$dest")"
	ln -sf "$src" "$dest"
	info "$dest -> $src"
}

step_dotfiles() {
	local pkg
	for pkg in bat fastfetch git kitty nvim qt6ct quickshell ruff sway tmux wallpapers yazi zsh; do
		link "$DOTFILES/$pkg" "$XDG_CONFIG_HOME/$pkg"
	done
	link "$DOTFILES/gtk" "$XDG_CONFIG_HOME/gtk-3.0" # same gtk.css + settings.ini for GTK 3 and 4
	link "$DOTFILES/gtk" "$XDG_CONFIG_HOME/gtk-4.0"
	link "$DOTFILES/jj/config.toml" "$XDG_CONFIG_HOME/jj/config.toml"
	link "$DOTFILES/containers/containers.conf" "$XDG_CONFIG_HOME/containers/containers.conf"
	link "$DOTFILES/containers/registries.conf" "$XDG_CONFIG_HOME/containers/registries.conf"
	link "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv" # only file in $HOME; bootstraps ZDOTDIR
	link "$DOTFILES/bin" "$HOME/.local/bin"      # qs-* helper scripts (sway binds + Quickshell call them)
	mkdir -p "$HOME/.local/state/qs/toggles"

	rm -f "$HOME/.zshrc" # install-time placeholder
	xdg-user-dirs-update
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

	# USB layout:
	#   keys/gpg/ic/public.asc                        YubiKey identity, public only
	#   keys/gpg/{pb,gx}/{public,secret-keys}.asc     on-disk identities
	#   keys/ssh/id_ed25519_{pb,gx}[.pub]
	local usb
	usb="$(mount_usb)" || {
		warn "Skipped key import - later: post-install.sh --redo keys"
		return 0
	}

	local id pub sec
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

	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	local k
	for k in id_ed25519_pb id_ed25519_gx; do
		if [[ -f "$usb/keys/ssh/$k" ]]; then
			install -m 600 "$usb/keys/ssh/$k" "$HOME/.ssh/$k"
			[[ -f "$usb/keys/ssh/$k.pub" ]] && install -m 644 "$usb/keys/ssh/$k.pub" "$HOME/.ssh/$k.pub"
			success "Installed SSH key: $k"
		else
			warn "No SSH key at $usb/keys/ssh/$k"
		fi
	done

	umount_usb

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

step_finish() {
	banner "Done"
	cat <<'EOF'

  Reboot → unlock LUKS (FIDO2 PIN + touch) → TTY1: touch the key, or unplug it and type the password → Sway.
  Re-run a step:  post-install.sh --redo <step>

EOF
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
