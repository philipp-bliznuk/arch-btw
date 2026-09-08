# Arch Linux Workstation Install Guide

```
LUKS2 → Btrfs subvolumes → UKI → systemd-boot → snapper + sdboot-snaps → Sway (Wayland) + Quickshell → AppArmor + Firejail + hardened sysctl → YubiKey (FIDO2 + OpenPGP)
```

`$DISK` = install target (`lsblk` to find it: `/dev/sda`, `/dev/nvme0n1`, …). `${DISK}1` = ESP, `${DISK}2` = LUKS. YubiKeys provisioned first per [YUBIKEY.md](./YUBIKEY.md).

---

## Step 0 — Flash the Arch ISO to USB

Download ISO + checksum from [archlinux.org/download](https://archlinux.org/download/).

```sh
sha256sum archlinux-x86_64.iso        # Linux — compare against sha256sums.txt
shasum -a 256 archlinux-x86_64.iso    # macOS
```

### macOS

```sh
diskutil list                                                       # spot the USB by size
diskutil unmountDisk /dev/disk4                                     # unmount, don't eject
sudo dd if=archlinux-x86_64.iso of=/dev/rdisk4 bs=4m status=progress
diskutil eject /dev/disk4
```

- `rdisk4` = raw whole-disk node, ~10× faster; no partition suffix. Lowercase `bs=4m` (GNU uses `4M`).
- `diskutil list` showing the flashed stick as `FDisk_partition_scheme` + a small `0xEF` + free space is normal — macOS can't see the ISO9660 payload. The write still worked.
- No `status=progress`? Drop it, press `Ctrl-T` mid-write for progress.

### Linux

```sh
lsblk                                                               # identify USB by size
sudo umount /dev/sdb*                                               # ignore "not mounted"
sudo dd if=archlinux-x86_64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sync && sudo eject /dev/sdb
```

- Write to the whole device (`/dev/sdb`), never a partition (`/dev/sdb1`).

**Won't boot from USB?** Disable Secure Boot in firmware first (re-enable in Step 9), and pick the `UEFI:` entry in the one-time boot menu, not Legacy/CSM.

---

## Step 1 — Boot the Live Environment

```bash
ping -c 3 archlinux.org          # wired usually just works

# Wi-Fi:
iwctl
#   station wlan0 scan
#   station wlan0 get-networks
#   station wlan0 connect "<SSID>"
#   exit
```

Continue over SSH (easier copy-paste):

```bash
passwd                           # temp root password for the live session
systemctl start sshd
ip addr show                     # find the IP, then: ssh root@<ip>
```

---

## Step 2 — Partition, Encrypt, Btrfs

```
${DISK}1  2G        EFI System Partition  (FAT32, /boot/efi)
${DISK}2  remainder LUKS2 container       (Btrfs subvolumes inside)
```

```bash
cfdisk $DISK
```

cfdisk TUI (arrows move, Enter selects):
1. Label → **`gpt`** (not dos/MBR).
2. Free space → `[New]` → `2G` → `[Type]` → **`EFI System`**.
3. Free space → `[New]` → default size (rest) → leave type `Linux filesystem`.
4. `[Write]` → `yes` → `[Quit]`. Nothing touches disk until Write.

```bash
lsblk                                            # verify ${DISK}1 (2G) + ${DISK}2

mkfs.fat -F32 ${DISK}1

cryptsetup luksFormat --type luks2 ${DISK}2      # argon2id KDF is the LUKS2 default
cryptsetup open ${DISK}2 cryptroot

mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs subvol create /mnt/@
btrfs subvol create /mnt/@home
btrfs subvol create /mnt/@snapshots
btrfs subvol create /mnt/@swap                   # own subvol: btrfs can't snapshot an active swapfile
umount /mnt

mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,.snapshots,swap,boot/efi}
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap     # no compression on swap
mount ${DISK}1 /mnt/boot/efi
```

Enroll both YubiKeys for touch-to-unlock (passphrase keyslot 0 stays as fallback). Run once per key, swapping keys between runs:

```bash
systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no ${DISK}2   # key #1
systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no ${DISK}2   # key #2
cryptsetup luksDump ${DISK}2                                                   # verify slots
```

- Enrollment **still asks for the FIDO2 PIN once** even with `--fido2-with-client-pin=no` — CTAP2 requires the PIN to *create* a credential. The flag governs *unlock* time, which stays touch-only.
- Installing over SSH: keys plug into the **target** machine's USB; touch prompts route over SSH fine.
- `libfido2` is auto-bundled by the `sd-encrypt` hook — no `BINARIES=` hack. Cmdline activation added in Step 5.

---

## Step 3 — Install Base System

```bash
pacstrap /mnt base linux linux-lts linux-firmware base-devel intel-ucode \
    git openssh btrfs-progs neovim networkmanager \
    pipewire pipewire-pulse wireplumber \
    sudo zsh efibootmgr snapper snap-pac \
    apparmor chrony firejail bubblewrap earlyoom ufw \
    pacman-contrib \
    polkit mesa sway swaylock swayidle \
    wl-clipboard grim slurp ghostty xorg-xwayland \
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji \
    brightnessctl playerctl xdg-user-dirs man-db man-pages \
    bluez bluez-utils \
    libqalculate systemd-ukify sbctl btrfs-assistant \
    pam-u2f libfido2 yubikey-manager ccid pcsc-tools \
    librewolf \
    eza fzf fd ripgrep bat zoxide yazi ouch tmux fastfetch git-delta lazygit jujutsu podman \
    poppler ffmpeg 7zip jq yq btop tree \
    tree-sitter-cli nodejs npm go python rustup uv bun

genfstab -U /mnt >> /mnt/etc/fstab
grep subvol /mnt/etc/fstab        # verify @, @home, @snapshots, @swap present

arch-chroot -S /mnt               # -S (ISO >=2025.10.01): real chroot so bootctl can write NVRAM
```

- `intel-ucode` assumes an Intel CPU — swap it for `amd-ucode` on AMD (never both).
- `-S` matters: plain `arch-chroot` fails silently on systemd v257+ (no NVRAM entry, no error).
- `waybar`/`mako`/`swaybg` deliberately absent — Quickshell replaces all four, installed in Step 8 (AUR). `swaylock`/`swayidle` stay here (security-critical, kept off the pre-1.0 shell).
- `polkit` gives the Wayland session a seat (else Sway exits with a permission error). `mesa` satisfies `opengl-driver`, `noto-fonts` satisfies `ttf-font` + CJK/emoji glyphs — both are virtual deps that halt pacstrap if unpicked.
- NVIDIA: swap `mesa` → `nvidia-open-dkms` + `linux-headers linux-lts-headers` + `nvidia-utils`; start Sway as `sway --unsupported-gpu`; check `dkms status` after kernel updates.
- Last three lines are the dotfiles toolchain (called by zsh/tmux/git/yazi/nvim) + Neovim's Mason toolchains + language runtimes. `librewolf` is in `extra` now — no AUR build.
- `rustup` ships no toolchain — run `rustup default stable` once post-boot (fills `~/.cargo/bin`, already on PATH via `.zshenv`).
- Mason needs `npm`/`go`/`python` present at first `nvim` launch or its LSP/formatter installs fail silently.
- `pinentry-curses` (Step 10) comes from `pinentry`, pulled in as a `gnupg` dependency — no extra package.
- pacstrap gpgme/library noise near the end is harmless.

---

## Step 4 — Configure the System

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "<hostname>" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   <hostname>.localdomain <hostname>
EOF

echo "KEYMAP=us" > /etc/vconsole.conf     # REQUIRED by sd-vconsole hook; sets LUKS-prompt layout

passwd                                     # root password

# Swap SIZE >= RAM for hibernation (whole memory image must fit). 16G assumes 16 GB RAM.
btrfs filesystem mkswapfile --uuid clear --size 16G /swap/swapfile
swapon /swap/swapfile
echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab

btrfs inspect-internal map-swapfile -r /swap/swapfile    # WRITE DOWN — Step 5 resume_offset
```

- Use `map-swapfile -r`, **not** `filefrag` — filefrag reports a virtual offset on Btrfs → silent resume failure.
- Replace `<hostname>` in both `/etc/hostname` and both places in `/etc/hosts`.

---

## Step 5 — Boot Engine (UKI + systemd-boot)

systemd-boot is part of `systemd`; it auto-discovers UKIs in `EFI/Linux/` on the ESP.

`/etc/mkinitcpio.conf`:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

- Never mix hook families. `systemd`+`sd-encrypt`+`sd-vconsole` go together; the busybox family is `udev`+`encrypt`+`keymap`. Mixing (e.g. `systemd`+`encrypt`) hangs LUKS unlock forever.
- No `btrfs` hook (single-device root); no busybox `resume` hook (the `systemd` hook provides resume).

Get the LUKS UUID:

```bash
blkid -s UUID -o value ${DISK}2
```

`/etc/cmdline.d/root.conf`:

```
rd.luks.name=<UUID>=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet lsm=landlock,lockdown,yama,apparmor,bpf rd.luks.options=<UUID>=fido2-device=auto
```

- No `lockdown=` mode: any lockdown mode (integrity included) refuses hibernation. This build picks hibernation; don't add `module.sig_enforce=1` either (blocks all DKMS/out-of-tree modules, unfixable on stock Arch kernel).
- `rd.luks.options=<UUID>=fido2-device=auto` (same UUID) activates touch-to-unlock at boot; falls back to passphrase if no key present.

`/etc/cmdline.d/resume.conf` (offset from Step 4):

```
resume=/dev/mapper/cryptroot resume_offset=<offset-from-Step-4>
```

Edit `/etc/mkinitcpio.d/linux.preset` — enable UKI lines, comment out image lines:

```
#default_image="/boot/initramfs-linux.img"
default_uki="/boot/efi/EFI/Linux/arch-linux.efi"
#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/boot/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

Edit `/etc/mkinitcpio.d/linux-lts.preset` the same (recovery-kernel UKI):

```
#default_image="/boot/initramfs-linux-lts.img"
default_uki="/boot/efi/EFI/Linux/arch-linux-lts.efi"
#fallback_image="/boot/initramfs-linux-lts-fallback.img"
fallback_uki="/boot/efi/EFI/Linux/arch-linux-lts-fallback.efi"
fallback_options="-S autodetect"
```

```bash
bootctl install
mkinitcpio -p linux
mkinitcpio -p linux-lts

systemctl enable NetworkManager sshd            # sshd is temporary — Step 8 #15 removes it
systemctl enable apparmor earlyoom chronyd systemd-resolved
systemctl enable snapper-timeline.timer snapper-cleanup.timer
systemctl enable fstrim.timer                   # do NOT also use the `discard` mount option
systemctl enable paccache.timer
# bluetooth.service intentionally NOT enabled — `systemctl enable --now bluetooth` when needed
```

- `mkinitcpio -p` prints `Secureboot key directory doesn't exist, not signing!` — harmless, keys don't exist until Step 9. UKIs build fine.
- `microcode` hook bundles CPU microcode into the `.efi`; no `initrd /intel-ucode.img` line needed.

System config files (still in chroot):

```bash
tee /etc/sysctl.d/99-hardening.conf <<'EOF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.tcp_syncookies = 1
EOF

# Domains=~. routes ALL lookups through Quad9/DoT (else per-link DHCP DNS runs in parallel).
tee /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
Domains=~.
EOF

sed -i 's/^pool/#pool/' /etc/chrony.conf        # drop unauthenticated pool, add Cloudflare NTS
tee -a /etc/chrony.conf <<'EOF'
server time.cloudflare.com iburst nts
minsources 1
EOF

mkdir -p /etc/systemd/journald.conf.d
tee /etc/systemd/journald.conf.d/00-size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
EOF

mkdir -p /etc/systemd/sleep.conf.d
tee /etc/systemd/sleep.conf.d/00-hibernate-delay.conf <<'EOF'
[Sleep]
HibernateDelaySec=1h
EOF

mkdir -p /etc/systemd/logind.conf.d
tee /etc/systemd/logind.conf.d/00-lid.conf <<'EOF'
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
HandleLidSwitchDocked=ignore
EOF

tee /etc/fonts/local.conf <<'EOF'
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
```

- `resolv.conf` symlink can't be made here (bind-mounted into chroot) — done in Step 8 #1.
- Alias `monospace` to `JetBrainsMono Nerd Font`, **not** the `...Mono` variant (Mono cramps/clips bar+terminal icons). Verify post-boot: `fc-match monospace`.
- Don't add `IdleAction=` to logind — Sway sets no idle hint, so it never fires. Idle is `swayidle` (Step 8 #12).

---

## Step 6 — Create Your User

```bash
useradd -m -G wheel -s /bin/zsh <yourname>
passwd <yourname>
EDITOR=nvim visudo                # uncomment: %wheel ALL=(ALL:ALL) ALL
```

---

## Step 7 — Exit Chroot and Reboot

```bash
swapoff -a                        # MUST be inside chroot (see below)
exit
umount -R /mnt
cryptsetup close cryptroot
reboot                            # remove install media
```

- `swapoff` here, not after `exit`: an active swapfile pins `cryptroot` → `cryptsetup close` fails "Device or resource busy". From the live shell `swapoff -a` can't find the chroot-relative `/swap/swapfile` path. If already out of chroot: `swapoff /mnt/swap/swapfile` then retry close, or just `reboot`.
- No `/etc/crypttab` needed — `sd-encrypt` unlocks LUKS in the initramfs.

---

## Step 8 — First Boot Setup

LUKS prompt appears — enter passphrase, or **insert + touch** YubiKey. A flashing key that seems to "hang" the boot is waiting for your touch, not stuck. Booting without a key falls back to the passphrase prompt (keyslot 0 always works).

SSH in as your user (`ssh <yourname>@<ip>`); use `sudo` for root. Sub-sections 1–13 work over SSH; #14 must be at the machine (Sway needs a local seat).

- First login runs `zsh-newuser-install` (no `~/.zshrc` yet) — press `q`, or `touch ~/.zshrc`. Real `.zshrc` arrives with dotfiles (#12).

### 1. Verify bootloader NVRAM entry + fix DNS

```bash
sudo bootctl status                          # entry missing? re-run: sudo bootctl install

efibootmgr                                   # list entries
sudo efibootmgr -b <id> -B                   # delete stale entries (partuuid ≠ current ESP)

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
resolvectl status                            # confirm DNS 9.9.9.9, +DNSOverTLS
```

- Delete only stale `Linux Boot Manager` / `Fallback Linux Boot Manager` entries whose partuuid differs from the ESP in `bootctl status`. Leave firmware/device entries alone.

### 2. Connect to Wi-Fi

```bash
nmcli device wifi list
nmcli device wifi connect "<SSID>" --ask     # saved profile auto-connects every boot
```

- iwctl (live ISO) does **not** persist — a machine installed over Ethernet then moved to Wi-Fi boots offline until this profile exists.

### 3. Complete snapper setup

`snapper create-config` needs D-Bus/snapperd (live boot only, not chroot):

```bash
sudo umount /.snapshots
sudo rm -r /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots

sudo snapper -c home create-config /home
sudo snapper -c home set-config \
    TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
    TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
```

- `snap-pac` hooks only the root config (`@home` gets timeline snapshots, none on package txns). Snapshots ≠ backups — same disk.

### 4. Back up the LUKS header

```bash
lsblk -f                                     # find the crypto_LUKS partition
sudo cryptsetup luksHeaderBackup <luks-partition> --header-backup-file /tmp/luks-header.img
```

Copy `/tmp/luks-header.img` to an encrypted USB, delete the local copy.

- Write to `/tmp` (tmpfs), **not** `~` — `@home` has its own snapper timeline, so a secret dropped there survives in snapshots after you delete it.
- Treat the file as a passphrase; re-take after any keyslot change (`luksAddKey`/`Remove`/`cryptenroll`).

### 5. Install yay (AUR helper)

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si
cd ~ && rm -rf /tmp/yay
```

### 6. Install sdboot-snaps

Removed from AUR — build from upstream:

```bash
git clone https://github.com/bkmo/sdboot-snaps /tmp/sdboot-snaps
cd /tmp/sdboot-snaps && makepkg -srci
cd ~ && rm -rf /tmp/sdboot-snaps

sudo sed -i 's|^#\?ESP=.*|ESP=/boot/efi|' /etc/sdboot-snaps.conf   # default is /efi
sudo systemctl enable --now sdboot-snaps-watch.path
```

- `MAX_UKIS` defaults to 7 (~1 GB); lower it if the ESP is tight.

### 7. Enable the firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit ssh                           # BEFORE enable — else it drops your SSH session
sudo ufw enable
```

- `ufw enable` also enables `ufw.service`; no separate `systemctl enable`. `limit` rate-limits repeated connections. Rule removed in #15.

### 8. YubiKey login + sudo

Touch either key to authenticate (password fallback). Generate the mapping **as your user** (`pamu2fcfg` prefixes it with whoever runs it). Key #1 for the first command, key #2 for the `-n` append:

```bash
sudo systemctl enable --now pcscd.socket
pamu2fcfg -o pam://arch-yubikey -i pam://arch-yubikey > /tmp/u2f_mappings
pamu2fcfg -n -o pam://arch-yubikey -i pam://arch-yubikey >> /tmp/u2f_mappings
sudo install -o root -g root -m 600 /tmp/u2f_mappings /etc/u2f_mappings
rm /tmp/u2f_mappings
```

First `auth` line in `/etc/pam.d/system-auth` (covers TTY login + sudo; reuse the exact origin/appid string):

```
auth sufficient pam_u2f.so authfile=/etc/u2f_mappings cue origin=pam://arch-yubikey appid=pam://arch-yubikey
```

- `pamu2fcfg` asks the FIDO2 PIN once here (CTAP2 credential creation) + touch. Day-to-day login/sudo/lock is touch-only.
- Keep a separate SSH session with a live `sudo -s` shell open while editing PAM; test in a fresh session before closing it.
- `/etc/pam.d/swaylock` includes `system-auth`, so the lock screen accepts a touch too — it won't render the `cue`, so with a key in it appears to pause until you touch. Password still works.

### 9. Install Quickshell (bar, launcher, notifications, wallpaper)

```bash
yay -S quickshell
```

- Pin to `quickshell` (tagged) over `quickshell-git` — pre-1.0, QML API churns. Qt6 deps auto-pulled.
- Ships **zero** UI — blank session until `~/.config/quickshell/` has a QML config (from your dotfiles, #12). Launched by `exec quickshell` in the Sway config; also your notification daemon now `mako` is gone — run one instance.

### 10. Configure LibreWolf (browser)

Installed from `extra` in Step 3. Configure via `librewolf.overrides.cfg` (AutoConfig JS, survives profile resets), not per-profile `user.js`. Location depends on build — check `about:support` → *Profile Directory*:

```
~/.librewolf/librewolf.overrides.cfg                      # most Linux builds
~/.config/librewolf/librewolf/librewolf.overrides.cfg     # XDG-path builds
```

```javascript
defaultPref("privacy.resistFingerprinting.letterboxing", true);   // adds letterbox bars
defaultPref("network.http.referer.XOriginPolicy", 2);            // may break login/checkout
defaultPref("media.autoplay.blocking_policy", 2);                // block audio AND video
defaultPref("librewolf.webgl.prompt", true);
defaultPref("librewolf.webgl.prompt.hide", false);
// Extension firewall — NOTE: stops uBlock Origin from updating its filter lists.
defaultPref("extensions.webextensions.base-content-security-policy",
            "default-src 'none'; script-src 'none'; object-src 'none';");
defaultPref("extensions.webextensions.base-content-security-policy.v3",
            "default-src 'none'; script-src 'none'; object-src 'none';");
```

- Don't re-enable Google Safe Browsing, don't set `resistFingerprinting` false, don't relax `security.OCSP.require` — LibreWolf already hardens these.
- No arkenfox `user.js` — written for desktop Firefox, fights LibreWolf's own prefs.

### 11. Application sandboxing + firecfg

```bash
sudo firecfg                     # symlinks Firejail-profiled apps into /usr/local/bin
```

- Re-run `sudo firecfg` after installing a new GUI app you want auto-sandboxed. Profiles: `/etc/firejail/*.profile`; overrides: `~/.config/firejail/`.
- One-off tighter jail: `bwrap --ro-bind / / --dev /dev --unshare-all --new-session ./suspicious-binary`

### 12. Install your dotfiles

```bash
mkdir -p ~/projects
git clone git@github.com:philipp-bliznuk/arch-btw.git ~/projects/dotfiles
cd ~/projects/dotfiles
./install.sh
xdg-user-dirs-update             # creates ~/Documents, ~/Downloads, ~/Pictures, …
```

- SSH clone needs your key (Step 10) — else clone HTTPS (`https://github.com/philipp-bliznuk/arch-btw.git`), switch remote later.
- `install.sh` symlinks each tool dir → `~/.config/<name>` and `zsh/.zshenv` → `$HOME/.zshenv` (which sets `ZDOTDIR=~/.config/zsh`). Nothing else — no packages, no theming, no services.

The symlinked `~/.config/sway/config` is a scaffold derived from stock `/etc/sway/config`; don't hand-edit stock. Key lines:

```
set $term ghostty
set $menu qs ipc call launcher toggle      # IPC pattern; no-op until your QML defines the handler

input * { xkb_layout "us" }                 # replace "us" for other layouts (+ xkb_variant/options)

exec quickshell                             # bar + launcher + notifications + wallpaper

bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0
bindsym --locked XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym --locked XF86AudioMute        exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym --locked XF86AudioMicMute     exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

exec swayidle -w \
    timeout 900  'pgrep -x swaylock || swaylock -f' \
    timeout 905  'swaymsg "output * power off"' \
         resume  'swaymsg "output * power on"' \
    timeout 1800 'systemctl suspend-then-hibernate' \
    before-sleep 'pgrep -x swaylock || swaylock -f'

bindsym Print exec grim -g "$(slurp)" ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png
```

- No stock `bar { }` block — Quickshell draws its own layer-shell bar; a bare `bar` block spawns a second swaybar.
- No `output * bg` line — `swaybg` not installed; Quickshell paints the wallpaper.
- Keep `include /etc/sway/config.d/*` — it pulls `50-systemd-user.conf` (exports session env for `xdg-desktop-portal-wlr`; dropping it breaks screen capture).
- `KEYMAP=us` (Step 4) covers TTY only — Sway needs its own `input` xkb block.
- `--locked` lets binds fire while `swaylock` is up; `-l 1.0` caps volume at 100%.
- Idle ladder: 15 min lock → +5 s screens off → 30 min suspend → ~1 h hibernate. `before-sleep` keeps it locked across sleep; `swayidle -w` holds the sleep inhibitor until lock is up. Session-scoped — bare TTY/SSH never sleeps. Tune timings in dotfiles.

### 13. Audio

PipeWire is socket-activated — starts on demand inside Sway, no manual enable.

### 14. Start Sway

`~/.config/zsh/.zprofile` (symlinked in #12) runs `exec sway` on TTY1 login. Nothing to write by hand — shown for reference:

```sh
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
    exec sway
fi
```

Move to the machine, log in as `<yourname>` on TTY1 — that login *is* the test. Land back at a shell? Run `sway` by hand to read the error (typo in config, missing GPU driver, or seat/permission → needs `polkit`).

Optional autologin — only **after** Sway starts cleanly (a broken Sway becomes a silent relogin loop):

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin <yourname> --noclear %I $TERM
EOF
```

### 15. Close the remote-access door

```bash
sudo systemctl disable --now sshd
sudo ufw delete limit ssh
ss -tlnp | grep :22              # should print nothing
sudo ufw status
```

Re-enable later key-only if needed:

```bash
sudo mkdir -p /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers <yourname>
EOF
sudo systemctl enable --now sshd
sudo ufw limit ssh
```

- Put your public key in `~/.ssh/authorized_keys` **before** enabling — else you lock out the remote path.

**Recovery after a bad update:**
1. Reboot → hold Space → select the pre-update snapshot. Boots writable, but temporary (default target unchanged).
2. Confirmed good? `sudo btrfs-assistant` → Snapshots → select → Restore (Arch layout swaps `@` for a fresh RW copy; `rootflags=subvol=@` keeps working).
3. Reboot normally.

- **Not** `snapper rollback` — that assumes the openSUSE layout. `btrfs-assistant` is correct for `@`/`@home`/`@snapshots`.

---

## Step 9 — Secure Boot

Enforcement layer on top of the UKI (firmware refuses `.efi` files you didn't sign). Key-based — no TPM. Machine must boot UEFI, not Legacy/CSM.

```bash
# 1. Firmware → Setup Mode: reboot → UEFI setup (F2/F10/F12/Del) → Security/Boot →
#    "Clear/Delete all Secure Boot keys" → save & exit → boot back in.
sudo sbctl status                     # confirm: Setup Mode: Enabled

# 2. Create + enroll your keys (+ Microsoft keys for signed option ROMs / dual-boot)
sudo sbctl create-keys
sudo sbctl enroll-keys --microsoft
#   "File is immutable"? → sudo chattr -i /sys/firmware/efi/efivars/{KEK,db,PK}-*  then retry

# 3. Sign UKIs + bootloader
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-fallback.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-lts.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-lts-fallback.efi
sudo sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/efi/EFI/BOOT/BOOTX64.EFI

# 4. Sign the bootloader SOURCE copy too — systemd-boot-update.service copies it on next boot
sudo sbctl sign -s \
  -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
     /usr/lib/systemd/boot/efi/systemd-bootx64.efi

# 5. Verify — all files show ✓
sudo sbctl verify

# 6. Firmware → Security → Secure Boot: Enabled → save & exit.
```

- Step 4 prevents an unsigned bootloader landing on the ESP after a systemd upgrade (`bootctl` prefers `.efi.signed`). Re-run it if `sbctl verify` ever flags the bootloader.
- `zz-sbctl.hook` re-signs UKIs on every kernel/systemd upgrade automatically.
- Set `SBCTL=true` in `/etc/sdboot-snaps.conf` so snapshot UKIs are signed too.

---

## Step 10 — Wire Up Hardware Keys: GPG + SSH

Connects the **already-provisioned** identity (both keys carry the same S/E/A subkeys, applet hardened, from [YUBIKEY.md](./YUBIKEY.md)) to this machine. Best done locally from a Sway terminal, not SSH (PIN prompts via `pinentry-curses`).

```bash
# 1. Smartcard daemon (already done if you did Step 8 #8)
sudo systemctl enable --now pcscd.socket

# 2. Let GnuPG share the device (else scdaemon grabs it exclusively, ykman breaks)
mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
cat > ~/.gnupg/scdaemon.conf <<'EOF'
disable-ccid
pcsc-shared
EOF

# 3. Import public key + trust (copy public.asc + ownertrust.txt from YUBIKEY.md backup)
gpg --import public.asc
gpg --import-ownertrust ownertrust.txt
gpg --card-status                     # with a key in: creates on-disk stubs pointing at the card
```

gpg-agent — pinentry, SSH support, 1-week PIN cache:

```bash
cat > ~/.gnupg/gpg-agent.conf <<'EOF'
pinentry-program /usr/bin/pinentry-curses
enable-ssh-support
default-cache-ttl 604800
max-cache-ttl 604800
EOF
gpgconf --kill gpg-agent
```

Add to `~/.zshrc` (**not** `.zprofile` — that ends in `exec sway` and never returns):

```zsh
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
gpg-connect-agent updatestartuptty /bye >/dev/null
```

Git commit signing (find the `usage: S` subkey via `gpg --list-secret-keys --keyid-format long`, shows as `ssb>`):

```bash
git config --global user.signingkey <signing-subkey-id>!   # trailing ! pins to this subkey
git config --global commit.gpgsign true
git config --global gpg.format openpgp
gpg --armor --export <key-id>          # upload PRIMARY key id to GitHub → SSH and GPG keys
```

SSH from the auth subkey:

```bash
ssh-add -L                             # ssh-ed25519 line backed by the card → add to GitHub/hosts
```

- Prints nothing? Agent hasn't picked up SSH support — re-login (or `gpg-connect-agent updatestartuptty /bye`) with a card in.
- Card not seen after a swap: `gpg-connect-agent "scd serialno" "learn --force" /bye`. Signing hangs ~15 s = waiting for touch.
- Card not detected at all: check `pcscd`, `scdaemon.conf`, then `gpgconf --kill scdaemon`.
- GPG signing key uploads to all GitHub accounts; SSH auth key is one-account-only (others: HTTPS/deploy key).
