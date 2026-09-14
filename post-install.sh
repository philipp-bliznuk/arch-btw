#!/usr/bin/env bash
#
# Arch Linux — post-install (first boot). Run as your user from TTY2 (Ctrl-Alt-F2):
#   ~/projects/dotfiles/post-install.sh
#
# TTY1 runs `exec sway` once the dotfiles are linked; TTY2 stays a plain shell.
# Resumable: markers under ~/.local/state/arch-btw/done/<step>.
#
# Flags:  --list          step status
#         --redo <step>   re-run one step
#         --autologin     getty@tty1 autologin drop-in (only after Sway boots cleanly)
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
	"snapper:step_snapper"
	"luks_header:step_luks_header"
	"sdboot_snaps:step_sdboot_snaps"
	"firewall:step_firewall"
	"yubikey_pam:step_yubikey_pam"
	"librewolf:step_librewolf"
	"firecfg:step_firecfg"
	"dotfiles:step_dotfiles"
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
		warn "$fstype stick — files may be unreadable as $USER; prefer FAT/exFAT."
		sudo mount "$part" "$USB_MNT"
		;;
	esac
	printf '%s\n' "$USB_MNT"
}

umount_usb() {
	sync
	sudo umount "$USB_MNT" 2>/dev/null || true
	success "USB unmounted — safe to remove."
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
	err "Step NOT marked done — fix the cause and re-run to resume here."
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
			warn "No NVRAM entry points at the current ESP — re-running bootctl install."
			sudo bootctl install
		fi
	else
		warn "Could not read the ESP partuuid — inspect \`efibootmgr\` manually."
	fi

	sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
	resolvectl status | grep -i 'DNS Server' || true
}

step_network() {
	if curl -fsSI --max-time 5 https://archlinux.org >/dev/null 2>&1; then
		success "Online."
		return 0
	fi
	warn "Offline — connecting Wi-Fi."
	nmcli device wifi list
	local ssid
	printf 'SSID: ' >/dev/tty
	read -r ssid </dev/tty
	nmcli device wifi connect "$ssid" --ask
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
		warn "Skipped — back up the LUKS header later."
		return 0
	}

	# Never to ~ — @home snapshots would keep a copy.
	sudo cryptsetup luksHeaderBackup "$luks" \
		--header-backup-file "$dest/luks-header-$(date +%Y%m%d).img"
	success "Header written. Re-take after any keyslot change."
	umount_usb
}

step_sdboot_snaps() {
	if ! command -v sdboot-snaps >/dev/null && ! pacman -Q sdboot-snaps >/dev/null 2>&1; then
		rm -rf /tmp/sdboot-snaps
		git clone https://github.com/bkmo/sdboot-snaps /tmp/sdboot-snaps
		(cd /tmp/sdboot-snaps && makepkg -srci --noconfirm)
		rm -rf /tmp/sdboot-snaps
	fi
	sudo sed -i 's|^#\?ESP=.*|ESP=/boot/efi|' /etc/sdboot-snaps.conf # default is /efi
	sudo systemctl enable --now sdboot-snaps-watch.path
}

step_firewall() {
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	sudo ufw --force enable
}

step_yubikey_pam() {
	sudo systemctl enable --now pcscd.socket

	local tmp
	tmp="$(mktemp)"
	pause "Insert YubiKey #1, then Enter (asks FIDO2 PIN once + touch)"
	pamu2fcfg -o pam://arch-yubikey -i pam://arch-yubikey >"$tmp"
	pause "Now swap to YubiKey #2, then Enter"
	pamu2fcfg -n -o pam://arch-yubikey -i pam://arch-yubikey >>"$tmp"

	sudo install -o root -g root -m 600 "$tmp" /etc/u2f_mappings
	rm -f "$tmp"

	local pam=/etc/pam.d/system-auth
	local rule='auth sufficient pam_u2f.so authfile=/etc/u2f_mappings cue origin=pam://arch-yubikey appid=pam://arch-yubikey'
	if ! grep -qF 'pam_u2f.so' "$pam"; then
		sudo sed -i "0,/^auth/s|^auth|${rule}\n&|" "$pam" # first auth line
		success "pam_u2f added to $pam."
	else
		success "pam_u2f already configured."
	fi

	info "Testing (touch a key):"
	sudo -k
	sudo true && success "sudo works." || warn "Test failed — password still works; verify $pam before logging out."
}

step_librewolf() {
	mkdir -p "$HOME/.librewolf"
	cat >"$HOME/.librewolf/librewolf.overrides.cfg" <<'EOF'
defaultPref("privacy.resistFingerprinting.letterboxing", true);
defaultPref("network.http.referer.XOriginPolicy", 2);
defaultPref("media.autoplay.blocking_policy", 2);
defaultPref("librewolf.webgl.prompt", true);
defaultPref("librewolf.webgl.prompt.hide", false);
// Extension CSP firewall — blocks uBlock Origin filter-list updates.
defaultPref("extensions.webextensions.base-content-security-policy",
            "default-src 'none'; script-src 'none'; object-src 'none';");
defaultPref("extensions.webextensions.base-content-security-policy.v3",
            "default-src 'none'; script-src 'none'; object-src 'none';");
EOF
	success "librewolf.overrides.cfg written."
}

step_firecfg() {
	sudo firecfg # jails: ssh man wget librewolf ffplay. Blacklist misbehaving tools in /etc/firejail/firecfg.config.
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
	for pkg in bat fastfetch ghostty git nvim quickshell ruff sway tmux wallpapers yazi zsh; do
		link "$DOTFILES/$pkg" "$XDG_CONFIG_HOME/$pkg"
	done
	link "$DOTFILES/jj/config.toml" "$XDG_CONFIG_HOME/jj/config.toml"
	link "$DOTFILES/containers/containers.conf" "$XDG_CONFIG_HOME/containers/containers.conf"
	link "$DOTFILES/containers/registries.conf" "$XDG_CONFIG_HOME/containers/registries.conf"
	link "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv" # only file in $HOME; bootstraps ZDOTDIR

	rm -f "$HOME/.zshrc" # install-time placeholder
	xdg-user-dirs-update
	rustup default stable
	success "Dotfiles linked."
}

step_keys() {
	sudo systemctl enable --now pcscd.socket
	GPG_TTY="$(tty)"
	export GPG_TTY # pinentry-curses needs the tty while stdout is piped

	mkdir -p "$HOME/.gnupg"
	chmod 700 "$HOME/.gnupg"
	cat >"$HOME/.gnupg/scdaemon.conf" <<'EOF'
disable-ccid
pcsc-shared
EOF
	cat >"$HOME/.gnupg/gpg-agent.conf" <<'EOF'
pinentry-program /usr/bin/pinentry-curses
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
		warn "Skipped key import — later: post-install.sh --redo keys"
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
	gpg --card-status || warn "Card not seen — check pcscd / scdaemon.conf."

	SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
	export SSH_AUTH_SOCK
	gpg-connect-agent updatestartuptty /bye >/dev/null || true

	ssh-add -L 2>/dev/null | grep -i 'cardno:' >"$HOME/.ssh/id_ed25519_ic_yubikey.pub" || true
	if [[ -s "$HOME/.ssh/id_ed25519_ic_yubikey.pub" ]]; then
		chmod 644 "$HOME/.ssh/id_ed25519_ic_yubikey.pub"
		success "Exported YubiKey SSH public key."
	else
		warn "No card SSH key — later: ssh-add -L | grep cardno: > ~/.ssh/id_ed25519_ic_yubikey.pub"
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

  Reboot → unlock LUKS → log in on TTY1 → Sway.
  Passwordless TTY1 (after Sway boots clean):  post-install.sh --autologin
  Re-run a step:                               post-install.sh --redo <step>

EOF
}

do_autologin() {
	sudo_keepalive
	sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
	sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USER --noclear %I \$TERM
EOF
	sudo systemctl daemon-reload
	success "Autologin enabled for $USER on TTY1."
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
--autologin) do_autologin ;;
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
