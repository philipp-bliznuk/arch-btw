# Arch Linux Workstation Install Guide

## Philosophy

This is a workstation built for one person. No display manager, no desktop
environment, no abstraction layers between you and the system. You log in on
TTY1 and a Wayland tiling compositor takes over.

Every decision optimises for four things:

**Transparency.** You understand every component because you put it there.
systemd-boot over GRUB because it's simpler. UKI because it collapses kernel +
initramfs + cmdline into one signed artifact. Btrfs because snapshots are free
and instant.

**Recoverability.** Every pacman transaction is bookended by automatic snapshots.
Bad update? Reboot, hold Space at the boot menu, and pick the pre-update
snapshot — you're back in a working system in ~10 seconds. That boot is a full,
writable snapshot. Once you've confirmed it's good, one command promotes it to
the new default so it survives future reboots. A `linux-lts` kernel is installed
as a second boot entry, so even a broken mainline kernel never leaves you
stranded. No reinstalls, no rescue USBs.

**Security & Privacy.** Wayland isolates every window at the protocol level — no
client can silently keylog, screen-scrape, or inject into another, the way any
X11 client can. On top of that: full-disk LUKS2 encryption, Secure Boot with
your own keys (sbctl), a moderate kernel-hardening baseline (hardened sysctl,
Yama, Landlock, AppArmor MAC), per-application sandboxing (Firejail +
Bubblewrap), an authenticated privacy network layer (DNS-over-TLS to Quad9, NTS
time sync), and a `ufw` firewall that denies inbound by default. Hardware
security keys (YubiKey) anchor the whole chain: touch-to-unlock the disk,
touch-to-login/sudo, and touch-to-sign Git commits — with a passphrase fallback
kept on every path.

**Minimalism.** No PulseAudio (PipeWire handles everything), no NetworkManager
GUI (nmcli is enough), no login greeter (TTY + compositor). Wayland folds the
window manager, compositor, and display server into a single process, so there
is one less moving part than X11. Quickshell earns its Qt6 footprint by folding
the bar, launcher, notification daemon, and wallpaper into one shell process
instead of four separate tools — and the cosmetic layer stays cleanly split from
the security layer (swaylock, swayidle, and the compositor itself never depend
on it). If it doesn't earn its place, it doesn't get installed.

**The full stack:**

```
LUKS2 → Btrfs subvolumes → UKI → systemd-boot → snapper + sdboot-snaps → Sway (Wayland) + Quickshell → AppArmor + Firejail + hardened sysctl → YubiKey (FIDO2 + OpenPGP)
```

---

## Before You Start

**Identify your disk.** It could be `/dev/sda` (SATA/USB), `/dev/nvme0n1`
(NVMe), or something else. Run `lsblk` to check. Throughout this guide,
substitute `$DISK` with your actual device (e.g. `/dev/sda`), `${DISK}1` for
the first partition, and `${DISK}2` for the second.

**Partition plan:**

```
${DISK}1  2G        EFI System Partition  (FAT32, mounted at /boot/efi)
${DISK}2  remainder LUKS2 container       (Btrfs subvolumes inside)
```

No separate `/boot` — with UKI the kernel, initramfs, and cmdline are bundled
into a single `.efi` file that lives on the EFI partition. Use 2 GB for the
ESP: `sdboot-snaps` generates a UKI (~100–150 MB) per snapshot, and 7 snapshot
UKIs plus the default + fallback UKIs will overflow a 1 GB partition within
weeks.

---

## Step 1 — Boot the Live Environment

Boot the Arch ISO. You're now in a root shell on the live system.

**Connect to the internet:**

```bash
# Wired — usually works automatically. Verify:
ping -c 3 archlinux.org

# Wi-Fi — use iwctl:
iwctl
# Inside iwctl:
#   station wlan0 scan
#   station wlan0 get-networks
#   station wlan0 connect "<SSID>"
#   exit
```

**Optional — continue the install over SSH** (easier to copy-paste from your
main machine):

```bash
# Set a temporary root password for the live session
passwd

# Start sshd
systemctl start sshd

# Find the IP address
ip addr show

# From your main machine:
#   ssh root@<ip-address>
```

---

## Step 2 — Partition, Encrypt, and Set Up Btrfs

> **Using YubiKeys?** Provision them first — see [YUBIKEY.md](./YUBIKEY.md), an
> optional prerequisite. The FIDO2 enrollment below assumes each key already has
> a FIDO2 PIN set.

```bash
# 1. Partition the disk
#    p1: 2G  → EFI System
#    p2: remainder → Linux filesystem
cfdisk $DISK

# 2. Format the EFI partition
mkfs.fat -F32 ${DISK}1

# 3. LUKS2 encryption
#    argon2id KDF is the LUKS2 default — no extra flags needed
cryptsetup luksFormat --type luks2 ${DISK}2
cryptsetup open ${DISK}2 cryptroot

# 4. Create Btrfs subvolumes
mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs subvol create /mnt/@
btrfs subvol create /mnt/@home
btrfs subvol create /mnt/@snapshots
btrfs subvol create /mnt/@swap
umount /mnt

# 5. Mount with optimised options
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,.snapshots,swap,boot/efi}
mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap

# 6. Mount EFI
mount ${DISK}1 /mnt/boot/efi
```

> **Optional — enroll YubiKeys for touch-to-unlock (both keys present).**
> The passphrase slot you just created stays as the permanent fallback; each
> FIDO2 enrollment adds an _additional_ keyslot. Run once per key, swapping the
> key between runs. The `--fido2-with-client-pin=no` flag makes it **touch-only**
> (no PIN prompt) — this is recommended because each failed PIN attempt burns one
> of only 8 retries on the FIDO2 applet, and there is no way to unblock a locked
> PIN without a full FIDO2 reset:
>
> ```bash
> # Plug in key #1, then:
> systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no ${DISK}2
> # Unplug #1, plug in key #2, then run the exact same command again:
> systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no ${DISK}2
> ```
>
> This enrolls two independent FIDO2 slots (either key unlocks) plus the
> passphrase slot. It requires a YubiKey 5-series (hmac-secret support). The
> cmdline option that activates touch-at-boot is added in Step 5; `libfido2` is
> bundled into the initramfs automatically by the `sd-encrypt` hook — no
> `BINARIES=` hack needed. Verify enrolled tokens any time with
> `cryptsetup luksDump ${DISK}2`.
>
> **If your key already has a FIDO2 PIN set, enrollment will still ask for it
> once.** That is not the flag failing. CTAP2 requires the PIN to *create* a new
> credential on an authenticator that has one configured — common if you already
> use the key for WebAuthn logins. `--fido2-with-client-pin=no` governs whether a
> PIN is demanded at **unlock time**, which is the part that matters here: after
> enrollment, booting is touch-only.
>
> **Installing over SSH?** The keys must be plugged into the **target machine's**
> USB (where you're installing), not your laptop. The touch prompts route over
> the SSH session fine — just touch the key on the target when prompted.
>
> **FIDO2 PIN vs OpenPGP PINs — these are completely separate.** The FIDO2
> applet has its own PIN (or none, with `--fido2-with-client-pin=no` above).
> The OpenPGP applet (Step 10) has a different user PIN and admin PIN. They do
> not share any credential. See the [Credentials Reference](#credentials-reference)
> table at the end of this guide for the full map.

---

## Step 3 — Install Base System

```bash
# Install ALL packages in one shot.
# Replace <intel-ucode|amd-ucode> with the one matching your CPU — not both.
pacstrap /mnt base linux linux-lts linux-firmware base-devel \
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
    <intel-ucode|amd-ucode>

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
# Verify all subvolumes are present (@, @home, @snapshots, @swap):
grep subvol /mnt/etc/fstab

# Chroot into the new system. The -S flag (Arch ISO >=2025.10.01) does a real
# chroot without a PID namespace, so `bootctl install` can write the NVRAM boot
# entry — plain `arch-chroot` fails silently on systemd v257+ (see Troubleshooting).
arch-chroot -S /mnt
```

> Everything is pacstrap'd up front: base system, desktop stack (Sway +
> ghostty), hardening (AppArmor, chrony, Firejail, earlyoom, ufw),
> YubiKey stack (pam-u2f, libfido2, ykman, ccid, pcsc-tools), and Secure Boot
> tooling (sbctl, systemd-ukify). `linux-lts` is the recovery kernel (second UKI
> in Step 5). Skip YubiKey packages if you're not using hardware keys.
>
> **The bar, launcher, notifications, and wallpaper come later.** Those all live
> in Quickshell — a single QtQuick/QML shell process — which is AUR-only and so
> gets installed in Step 8 after `yay` exists. That's why `waybar`, `mako`, and
> `swaybg` are **not** in this pacstrap. Its Qt6 dependencies
> (`qt6-declarative`, `qt6-wayland`, …) are pulled in automatically at that point.
> `swaylock` and `swayidle` stay here in the base install on purpose: the
> lock/idle path is security-critical and must never depend on a pre-1.0 cosmetic
> shell, so it stays on dedicated, boring C tools.

> **Four package choices worth explaining.**
>
> `polkit` is what gives your Wayland session a seat. Sway lists it as an
> optional dependency — "required if not using seatd service". Without either
> `polkit` or an enabled `seatd.service` (plus your user in the `seat` group),
> Sway exits immediately with a permission error. `polkit` is the fewer-moving-
> parts option and most of the desktop stack wants it anyway.
>
> `mesa` and `noto-fonts` are both here to satisfy **virtual dependencies** that
> would otherwise stop the install dead. Sway pulls in `wlroots`, which
> hard-depends on `opengl-driver`; that name is provided by several packages
> (`mesa`, `mesa-amber`, `nvidia-utils`, …), so with no explicit pick pacman
> halts mid-`pacstrap` to ask you to choose. Same story for `ttf-font`: Sway
> hard-depends on it and `ttf-jetbrains-mono-nerd` is **not** one of its
> providers. `noto-fonts` + `noto-fonts-emoji` also cover the glyphs JetBrains
> Mono doesn't ship (CJK, emoji), so nothing renders as boxes. Step 5 wires
> JetBrains Mono Nerd Font up as the system default.
>
> On NVIDIA, swap `mesa` for one of the `nvidia-open` packages plus
> `nvidia-utils` — `nvidia-utils` provides `opengl-driver` too. Note that
> `nvidia`, `nvidia-lts`, and `nvidia-dkms` no longer exist: Arch now ships only
> NVIDIA's **open** kernel modules, which cover Turing and newer. On Maxwell or
> Pascal you want the legacy AUR driver or the in-tree `nouveau` path (`mesa`).
>
> Because this guide installs **two** kernels, prefer the DKMS package:
> `nvidia-open-dkms` plus `linux-headers linux-lts-headers`. That's one module
> package that rebuilds itself for both kernels, versus keeping `nvidia-open` and
> `nvidia-open-lts` in lockstep — and their dependency on `linux`/`linux-lts` is
> unversioned, so pacman won't stop you from ending up with a module built against
> a kernel you no longer run. After any kernel update, check `dkms status` before
> rebooting: a failed rebuild scrolls past mid-upgrade and pacman still exits 0.
>
> One extra step regardless of which package you pick: wlroots does not officially
> support the NVIDIA driver, so Sway must be started as `sway --unsupported-gpu`.
> That means editing the `exec sway` line in `~/.config/zsh/.zprofile` (Step 8
> #13). Kernel
> mode setting needs no cmdline flag any more — `nvidia-utils` enables
> `nvidia_drm.modeset` by default on current drivers. If you have the choice, an
> AMD or Intel GPU on `mesa` is the path this guide is built for.
>
> `pacman-contrib` ships `paccache`, which prunes the package cache on a timer
> (enabled in Step 5). Without it `/var/cache/pacman/pkg` grows forever — and
> since it lives on `@`, every snapshot carries the bloat.
>
> `bluez` and `bluez-utils` are installed but **`bluetooth.service` is left
> disabled** (Step 5). A radio that is off by default is one less attack surface;
> `sudo systemctl enable --now bluetooth` when you actually need it.

> **Why `brightnessctl`, `playerctl`, `xdg-desktop-portal-gtk`.** Sway's stock
> config — the file you copy in Step 8 — already binds the laptop function keys
> to `brightnessctl` and `playerctl`, and the GTK portal is what makes file
> pickers work in Wayland apps. Skip them and those keybinds silently do nothing.
> Volume keys get rewired to wireplumber's `wpctl` in Step 8 instead.

---

## Step 4 — Configure the System

```bash
# Timezone and clock
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "<hostname>" > /etc/hostname

# Static hosts table — use the SAME name you just wrote to /etc/hostname.
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   <hostname>.localdomain <hostname>
EOF

# Console keymap — CRITICAL: sd-vconsole hook requires this file.
# Without it the LUKS password prompt may use the wrong keyboard layout.
echo "KEYMAP=us" > /etc/vconsole.conf

# Root password
passwd

# Swapfile (no compression on the swap subvol — correct by design)
# SIZE IT >= YOUR RAM if you want hibernation — the whole memory image has to
# fit in swap. 16G assumes a 16 GB machine; on 32 GB use --size 32G.
btrfs filesystem mkswapfile --uuid clear --size 16G /swap/swapfile
swapon /swap/swapfile
echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab

# Physical offset of the swapfile — WRITE THIS NUMBER DOWN, Step 5 needs it.
btrfs inspect-internal map-swapfile -r /swap/swapfile
```

> **About that offset.** `map-swapfile -r` prints the device-physical offset in
> page units, exactly what `resume_offset=` expects. Do **not** use `filefrag`:
> on Btrfs it reports a virtual logical address, which produces a plausible-looking
> but wrong number and a machine that silently refuses to resume. `map-swapfile`
> also validates the swapfile's requirements (no holes, single device, single data
> profile) — `mkswapfile` already satisfies all of them.

> **Why `@swap` is its own subvolume.** Btrfs cannot snapshot a subvolume that
> contains an active swapfile. Keeping the swapfile on `@swap` instead of `@` is
> what lets snapper, snap-pac, and the rollback flow keep working with hibernation
> enabled.

> **On `/etc/hosts`.** glibc's `nss-myhostname` (wired into Arch's default
> `/etc/nsswitch.conf`) already resolves your own hostname, so the file is not
> strictly required. It costs one heredoc and removes a whole class of reports —
> `sudo` pausing for seconds, or an app failing to resolve the machine's own
> name — so write it anyway. Replace `<hostname>` in **both** places.

---

## Step 5 — Boot Engine (UKI + systemd-boot)

systemd-boot is part of `systemd` — no extra package needed. It auto-discovers
UKIs placed in `EFI/Linux/` on the EFI partition.

**Edit `/etc/mkinitcpio.conf`** — use the systemd-based hook set:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

> **Do NOT mix hook families.** `systemd` + `sd-encrypt` + `sd-vconsole` belong
> together. The busybox equivalents (`udev` + `encrypt` + `keymap`) are a
> separate family. Mixing them (e.g. `systemd` + `encrypt`) causes LUKS unlock
> to hang indefinitely. The `rd.luks.name=` cmdline option used below is
> systemd-specific; the busybox `encrypt` hook uses `cryptdevice=` instead.
>
> No `btrfs` hook — that's only for _multi-device_ Btrfs; a single-device root
> is handled by `filesystems`. `base` provides busybox emergency-shell binaries;
> `fsck` is a near no-op on Btrfs but harmless.

**Create `/etc/cmdline.d/root.conf`** with the kernel command line:

```
rd.luks.name=<UUID>=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet lsm=landlock,lockdown,yama,apparmor,bpf
```

> **Hardening flags.** `lsm=` sets the Linux Security Module stack order so
> AppArmor loads (enabled further down this step); `landlock`, `lockdown`,
> `yama`, and `bpf` are kernel defaults kept explicit.
>
> **Why no `lockdown=` mode.** Kernel lockdown separates UID 0 from ring 0: it
> refuses unsigned module loading, `/dev/mem` and `/dev/port` writes, MSR writes,
> `ioperm`/`iopl`, raw PCI access, ACPI `custom_method`, kexec of unsigned
> images — **and hibernation**. That last one is not negotiable and not limited to
> `confidentiality`: `LOCKDOWN_HIBERNATION` sits inside the *integrity* set, and
> the kernel refuses suspend-to-disk without checking whether the swap target is
> encrypted. So it's lockdown or hibernation, never both.
>
> This guide picks hibernation, because hibernation is the only sleep state where
> the LUKS master key actually leaves RAM. Suspend-to-RAM parks it in memory every
> time the lid shuts, and `swaylock` is a software gate — full-disk encryption only
> genuinely protects a machine that is off or hibernated. Lockdown, by contrast,
> defends against an attacker who *already has root*.
>
> If you'd rather have lockdown, append `lockdown=integrity` to the line above and
> delete the `resume.conf` block below (plus the hibernation wiring in Step 5's
> config files and Step 8 #11). Do not enable `module.sig_enforce=1` as a
> consolation prize either — it blocks every out-of-tree module, DKMS or prebuilt,
> and on a stock Arch kernel that cannot be worked around (see Troubleshooting).

> **Optional — YubiKey touch-to-unlock.** If you enrolled FIDO2 slots in Step 2,
> append `rd.luks.options=<UUID>=fido2-device=auto` to the line above (same
> `<UUID>` as `rd.luks.name`). Doing it now bakes the option into the first UKI
> built below — no rebuild/re-sign round-trip later. At boot you'll be prompted
> to touch the key; if no key is present, it falls back to the passphrase prompt.

Get the UUID of your LUKS partition:

```bash
blkid -s UUID -o value ${DISK}2
```

**Create `/etc/cmdline.d/resume.conf`** to enable hibernation, using the offset
you noted down in Step 4:

```
resume=/dev/mapper/cryptroot resume_offset=<offset-from-Step-4>
```

> **Hibernation wiring.** `resume=` points at the *unlocked mapper device* that
> holds the filesystem containing the swapfile — not at a swap device. A swapfile
> has no swap-type UUID of its own, which is why the offset is needed as well.
> `sd-encrypt` opens `cryptroot` in early userspace before resume runs, so the
> ordering already works out.
>
> **No extra hook is required.** The `systemd` hook already provides the resume
> mechanism. Do **not** add the busybox `resume` hook — that belongs to the other
> hook family and mixing them breaks LUKS unlock (see the warning above).
>
> **No `lockdown=` mode in `root.conf`** is what keeps hibernation permitted. Any
> lockdown mode — `integrity` included, not just `confidentiality` — refuses
> suspend-to-disk outright. See the hardening note above.
>
> Because this lives in `/etc/cmdline.d/`, mkinitcpio picks it up automatically and
> bakes it into **both** `arch-linux.efi` and `arch-linux-lts.efi` on the
> `mkinitcpio -p` runs below — no rebuild, and nothing to re-sign later in Step 9.

**Edit `/etc/mkinitcpio.d/linux.preset`** — enable both UKI lines and disable the
plain-image lines so mkinitcpio writes only UKIs (no redundant `initramfs-*.img`
in `/boot`). `PRESETS=('default' 'fallback')` is already the stock default:

```
#default_image="/boot/initramfs-linux.img"
default_uki="/boot/efi/EFI/Linux/arch-linux.efi"

#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/boot/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

> With UKI, the `microcode` hook bundles CPU microcode directly into the `.efi`
> file. No separate `initrd /intel-ucode.img` line is needed — that pattern
> belongs to non-UKI setups.

**Edit `/etc/mkinitcpio.d/linux-lts.preset`** the same way — this builds the
recovery-kernel UKI that gives you a second, independent boot entry:

```
#default_image="/boot/initramfs-linux-lts.img"
default_uki="/boot/efi/EFI/Linux/arch-linux-lts.efi"

#fallback_image="/boot/initramfs-linux-lts-fallback.img"
fallback_uki="/boot/efi/EFI/Linux/arch-linux-lts-fallback.efi"
fallback_options="-S autodetect"
```

**Install the bootloader, generate UKIs, and enable services (still in chroot):**

> **Expect a Secure Boot message here.** `sbctl` installs a `mkinitcpio` post
> hook, so both `mkinitcpio -p` runs below will print
> `Secureboot key directory doesn't exist, not signing!`. That is correct — the
> keys don't exist yet (Step 9 creates them, and Step 9 is optional). The hook
> exits cleanly and the UKIs build fine. On sbctl older than 0.15 this same hook
> failed hard instead, which is worth knowing if you're installing from an old ISO.

```bash
bootctl install
mkinitcpio -p linux
mkinitcpio -p linux-lts

# Enable services that need to be running on first boot.
# NetworkManager + sshd = network + SSH access after reboot. sshd is TEMPORARY:
# it exists so Step 8 can be driven over SSH, and Step 8 #14 turns it back off.
systemctl enable NetworkManager sshd

# Hardening / privacy daemons (ufw is armed by `ufw enable` in Step 8, not here)
systemctl enable apparmor earlyoom chronyd systemd-resolved

# Snapper timers — harmless no-ops until the snapper config exists (Step 8 #2)
systemctl enable snapper-timeline.timer snapper-cleanup.timer

# Weekly TRIM for the SSD (do NOT also use the `discard` mount option)
systemctl enable fstrim.timer

# Prune the pacman package cache on a timer (pacman-contrib)
systemctl enable paccache.timer

# Note what is deliberately NOT here: bluetooth.service. The radio stays off
# until you ask for it — `sudo systemctl enable --now bluetooth`.
```

**Write system config files (still in chroot):**

```bash
# Sysctl hardening baseline
tee /etc/sysctl.d/99-hardening.conf <<'EOF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.tcp_syncookies = 1
EOF

# DNS-over-TLS → Quad9. `Domains=~.` routes ALL lookups through this server
# (without it, per-link DHCP DNS from NetworkManager is queried in parallel and
# can bypass Quad9/DoT). The /etc/resolv.conf symlink is created post-boot in
# Step 8 — it cannot be made here (it's bind-mounted into the chroot).
tee /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
Domains=~.
EOF

# Chrony NTS — comment out the default unauthenticated pool, add Cloudflare NTS
sed -i 's/^pool/#pool/' /etc/chrony.conf
tee -a /etc/chrony.conf <<'EOF'
server time.cloudflare.com iburst nts
minsources 1
EOF

# Cap the journal. Unbounded, it grows to 10% of the filesystem — and since
# /var/log lives on @, every snapshot carries whatever it has accumulated.
mkdir -p /etc/systemd/journald.conf.d
tee /etc/systemd/journald.conf.d/00-size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
EOF

# How long the machine stays suspended before it flips to hibernate
mkdir -p /etc/systemd/sleep.conf.d
tee /etc/systemd/sleep.conf.d/00-hibernate-delay.conf <<'EOF'
[Sleep]
HibernateDelaySec=1h
EOF

# Closing the lid follows the same path as going idle
mkdir -p /etc/systemd/logind.conf.d
tee /etc/systemd/logind.conf.d/00-lid.conf <<'EOF'
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
HandleLidSwitchDocked=ignore
EOF

# System-wide fonts: JetBrains Mono Nerd Font for monospace, Noto for the rest
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

> `snap-pac` hooks into pacman and creates pre/post snapshots automatically,
> but it needs a working snapper config first — that gets created after booting
> natively (Step 8).

> **About those last two.** Both are drop-ins rather than rewrites of
> `sleep.conf` / `logind.conf`, because those ship as fully-commented vendor
> defaults and `systemd-sleep.conf(5)` recommends drop-ins for local changes.
> `HibernateDelaySec=` is read only by `systemd-suspend-then-hibernate.service`;
> on a machine with a battery the ACPI `_BTP` low-battery alarm (below 5 %) can
> flip it to hibernate before the hour elapses — whichever comes first. Add
> `HibernateOnACPower=no` if you'd rather it stay suspended indefinitely while
> plugged in. `HandleLidSwitchDocked=ignore` keeps an external-monitor setup
> awake when you close the laptop. Do **not** add `IdleAction=` to the logind
> drop-in: logind fires that off session idle hints and Sway never sets one, so
> it would silently never trigger. The idle timer is `swayidle`, wired up in
> Step 8 #11.

> **The font family string matters.** JetBrains Mono Nerd Font installs under
> two names: `JetBrainsMono Nerd Font` (ligatures on, glyphs allowed to be wider
> than one cell) and `JetBrainsMono Nerd Font Mono` (every glyph squeezed into a
> strict monospace cell). Aliasing `monospace` to the `Mono` variant is the usual
> cause of bar and terminal icons looking cramped or clipped, so the config above
> uses the non-`Mono` name. Verify after first boot with `fc-match monospace`.

---

## Step 6 — Create Your User

Create the user account here in the chroot. Sway, its config, and the
session-launch config are all set up after first boot in Step 8.

```bash
useradd -m -G wheel -s /bin/zsh <yourname>
passwd <yourname>
EDITOR=nvim visudo  # Uncomment: %wheel ALL=(ALL:ALL) ALL
```

---

## Step 7 — Exit Chroot and Reboot

```bash
# Still in the chroot: turn the swapfile back off.
# This MUST happen here, not after `exit` — see the note below.
swapoff -a

# Leave chroot
exit

# Clean up and reboot
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Remove the installation media when prompted.

> **No `/etc/crypttab` needed.** The `sd-encrypt` hook unlocks LUKS in the
> initramfs before systemd starts. `/etc/crypttab` is only for secondary
> encrypted volumes opened after boot.
>
> **Why `swapoff` has to run inside the chroot.** Step 4 activated
> `/swap/swapfile`, and an active swapfile pins the underlying
> `/dev/mapper/cryptroot` mapping — so `cryptsetup close` fails with "Device or
> resource busy" even after a clean `umount -R /mnt`. You cannot fix it from the
> live shell afterwards: `swapoff -a` works off `/proc/swaps`, which recorded the
> path as `/swap/swapfile` (chroot-relative), and that path doesn't exist from the
> live ISO's root — you get exit code 32 and the swap stays on. Doing it before
> `exit` sidesteps the whole thing.
>
> **If you already left the chroot** and hit the busy error, run
> `swapoff /mnt/swap/swapfile` (the live-root path), then retry
> `cryptsetup close cryptroot`. Failing that, just `reboot` — the mapping tears
> down cleanly at power-off and the disk unlocks normally next boot. Don't reach
> for `fuser`/`lsof`; they report every kernel PID and lead nowhere.

---

## Step 8 — First Boot Setup

The LUKS prompt should appear — enter your passphrase (or touch YubiKey if
enrolled). If the machine doesn't boot, see [Troubleshooting](#troubleshooting).

**SSH in as your user** (`ssh <yourname>@<ip>`). NetworkManager and sshd were
enabled in the chroot (Step 5), so the machine comes up on the network with SSH
running. Use `sudo` wherever root is needed. If you're at a local TTY instead,
log in as `<yourname>` and `sudo -s` for a root shell.

Sub-sections 1–12 all work fine over SSH. Sub-section 13 is where you have to be
at the machine — Sway needs a local seat and won't start over SSH.

> **First login as `<yourname>` drops you into a zsh setup wizard.** Your shell is
> zsh (Step 6) and there is no `~/.zshrc` yet, so zsh offers
> `zsh-newuser-install`. Press `q` to dismiss it — your real `~/.zshrc` comes from
> your dotfiles later. If you want it to stop asking in the meantime,
> `touch ~/.zshrc`.

### 1. Verify the bootloader NVRAM entry

```bash
sudo bootctl status
```

> If the entry is missing (e.g. you used plain `arch-chroot`, or your ISO
> predates the `-S` flag), the loader files are still on the ESP under
> `EFI/BOOT/BOOTX64.EFI` — a single-OS machine boots via that fallback anyway.
> To create an explicit NVRAM entry now, re-run `sudo bootctl install`.

Point `/etc/resolv.conf` at the systemd-resolved stub so the DoT/Quad9 config
from Step 5 takes effect (this couldn't be done in the chroot — the file is
bind-mounted there):

```bash
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
resolvectl status   # confirm: DNS Servers 9.9.9.9, +DNSOverTLS
```

### 2. Complete snapper setup

`snapper create-config` needs D-Bus/snapperd, which only run on a live boot (not
in a chroot). Unmount the existing `@snapshots`, let snapper create its own
subvolume, delete it, then restore the `@snapshots` mount:

```bash
sudo umount /.snapshots
sudo rm -r /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots
```

Give `/home` its own snapper config too — the root config only covers `@`:

```bash
sudo snapper -c home create-config /home
sudo snapper -c home set-config \
    TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
    TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
```

> `snap-pac` only hooks the **root** config, so `@home` gets timeline snapshots
> on the enabled `snapper-timeline.timer` but nothing on package transactions —
> which is what you want, since installing a package doesn't touch your data.
> These are snapshots, not backups: they live on the same disk and die with it.

### 3. Back up the LUKS header

The header holds every keyslot. Corrupt it and the data is unrecoverable even
with the correct passphrase — a two-second `dd` accident, a firmware bug, a bad
`cryptsetup` invocation.

There is no `$DISK` variable in this shell any more, and device names can differ
from what the live ISO showed, so confirm the partition first:

```bash
lsblk -f                                   # find the crypto_LUKS partition
sudo cryptsetup luksHeaderBackup /dev/sda2 \
    --header-backup-file /tmp/luks-header.img
```

Then copy `/tmp/luks-header.img` onto an encrypted USB stick and delete the local
copy.

> **Write it to `/tmp`, not your home directory.** `/tmp` is a tmpfs, so the file
> never touches the disk and is gone at the next reboot. Dropping it in `~` puts a
> passphrase-equivalent secret on `@home`, which now has its own snapper timeline
> (#2) — deleting the file afterwards does **not** remove it from the snapshots
> that already captured it.
>
> **Treat that file as a passphrase.** Anyone holding it plus any passphrase that
> was valid *when it was taken* can decrypt the disk — restoring an old header
> re-validates keyslots you later revoked. Take a fresh backup after any
> `luksAddKey` / `luksRemoveKey` / `systemd-cryptenroll` change.

### 4. Install yay (AUR helper)

AUR builds must run as your non-root user. `makepkg -si` prompts for your sudo
password to install the finished package:

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si
cd ~ && rm -rf /tmp/yay
```

### 5. Install sdboot-snaps

Generates a UKI per snapshot and populates the systemd-boot menu automatically.
The package was removed from the AUR — build from the upstream repo:

```bash
git clone https://github.com/bkmo/sdboot-snaps /tmp/sdboot-snaps
cd /tmp/sdboot-snaps && makepkg -srci
cd ~ && rm -rf /tmp/sdboot-snaps
```

Point ESP at `/boot/efi` and enable the file watcher so every new `snap-pac`
snapshot gets a matching boot-menu entry:

```bash
sudo sed -i 's|^#\?ESP=.*|ESP=/boot/efi|' /etc/sdboot-snaps.conf
sudo systemctl enable --now sdboot-snaps-watch.path
```

> ESP defaults to `/efi`; this setup uses `/boot/efi`, hence the `sed`.
> `MAX_UKIS` defaults to 7 (~1 GB); lower it if the ESP is tight.

### 6. Enable the firewall

Set the default policy, allow SSH back in, then activate it (`ufw enable` also
enables the `ufw.service` unit, so no separate `systemctl enable` is needed):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit ssh
sudo ufw enable
```

> **Why `limit ssh` before `enable`.** `default deny incoming` includes port 22.
> If you are working through SSH — which is what this step assumes — activating
> ufw without an exception drops your session mid-install and the rest of Step 8
> becomes unreachable. `ufw enable` prints "Command may disrupt existing ssh
> connections. Proceed with operation (y|n)?"; the rule above is what makes `y`
> safe. `limit` (rather than `allow`) additionally rate-limits repeated
> connections from the same address. The rule is temporary — #14 removes it along
> with `sshd` itself.

### 7. (Optional) YubiKey login + sudo

Touch either key to authenticate, with a password fallback. Start the smartcard
daemon socket (also needed for OpenPGP in Step 10), then register both keys into
**one** mapping line (the spec is one line per user).

The mapping must be generated **as your user** (`pamu2fcfg` prefixes the mapping
with the name of whoever runs it — run it as root and it registers `root`, not
`<yourname>`, and your login/sudo never matches). The `-o`/`-i` origin and app-id
are a fixed label — reuse the **exact same string** in the PAM line below.
Plug in key #1 for the first command, then key #2 for the `-n` append:

```bash
sudo systemctl enable --now pcscd.socket
pamu2fcfg -o pam://arch-yubikey -i pam://arch-yubikey > /tmp/u2f_mappings
pamu2fcfg -n -o pam://arch-yubikey -i pam://arch-yubikey >> /tmp/u2f_mappings
sudo install -o root -g root -m 600 /tmp/u2f_mappings /etc/u2f_mappings
rm /tmp/u2f_mappings
```

> **`pamu2fcfg` asks for the FIDO2 PIN once, here.** Registering a credential is
> a CTAP2 credential-creation call, so each key prompts for its FIDO2 PIN (set in
> YUBIKEY.md Part A3) plus a touch as you run the two commands above — same
> one-time prompt as the LUKS enrollment in Step 2. It's not an error. Day-to-day
> login/sudo/lock afterwards is touch-only; the PIN is not asked again.

Add this as the **first** `auth` line in `/etc/pam.d/system-auth` (covers TTY
login **and** sudo, which include `system-auth`). `sufficient` = touch either key
to authenticate, fall through to the password prompt if no key is present:

```
auth sufficient pam_u2f.so authfile=/etc/u2f_mappings cue origin=pam://arch-yubikey appid=pam://arch-yubikey
```

> **Don't lock yourself out.** Keep a separate SSH session with a live `sudo -s`
> shell open while editing PAM so a typo can't stop you fixing it. Test
> login/sudo in a fresh SSH session before closing the safety one.
>
> **This reaches the lock screen too.** `/etc/pam.d/swaylock` includes
> `system-auth`, so once the rule is in place `swaylock` also accepts a YubiKey
> touch. It won't say so — `swaylock` doesn't render the `cue` message — so with a
> key inserted the unlock appears to hang for a moment until you touch it. Typing
> your password still works either way.

### 8. Install Quickshell (AUR — bar, launcher, notifications, wallpaper)

`quickshell` is a QtQuick/QML toolkit that runs alongside Sway as a
`wlr-layer-shell` client. It's the one process that draws the top bar, the app
launcher, the notification popups, and the wallpaper — replacing what `waybar`,
`anyrun`, `mako`, and `swaybg` would each do separately. It's AUR-only:

```bash
yay -S quickshell
```

> At install time, check whether you want the tagged release (`quickshell`) or
> the latest commit (`quickshell-git`). Quickshell is pre-1.0 and its QML API
> still changes between releases, so pin to `quickshell` unless a shell config
> you're borrowing needs `-git`. Its Qt6 dependencies are pulled in automatically.

> Quickshell ships **zero** default UI. It renders **nothing** — no bar, no
> wallpaper, a blank session — until `~/.config/quickshell/` contains a QML shell
> config. That config is yours to write and lives in your dotfiles; see
> [Next Steps](#next-steps). It is launched once from the Sway config (`exec
> quickshell`, Step 8 #11) and is also your session's notification daemon now that
> `mako` is gone — run only one instance.

### 9. Install LibreWolf (browser)

LibreWolf is a privacy-hardened Firefox fork. It is AUR-only; use the prebuilt
binary — the plain `librewolf` package compiles the entire Firefox tree and takes
hours:

```bash
yay -S librewolf-bin
```

**Configuring it.** LibreWolf already ships most of the hardening you'd
otherwise hand-write: fingerprinting resistance on, telemetry stripped out,
Google Safe Browsing off, cookies and site data cleared on close, OCSP hard-fail.
Don't re-add any of that.

For your own changes, use `librewolf.overrides.cfg` rather than a per-profile
`user.js`. It is an AutoConfig file parsed as JavaScript, read on every startup,
and it survives profile resets and moves between machines cleanly. Its location
depends on the build — check `about:support` → *Profile Directory* if in doubt:

```
~/.librewolf/librewolf.overrides.cfg                      # most Linux builds
~/.config/librewolf/librewolf/librewolf.overrides.cfg     # XDG-path builds
```

Two functions are available: `defaultPref()` sets a default the user can still
change in the UI, `pref()` enforces the value as if it had been set manually.
A reasonable starting set, with what each one costs you:

```javascript
// Round the window's reported size to a coarse grid. Adds letterbox bars.
defaultPref("privacy.resistFingerprinting.letterboxing", true);

// Send no Referer on cross-origin requests. Breaks some login/checkout flows.
defaultPref("network.http.referer.XOriginPolicy", 2);

// Block autoplay for audio AND video, not just audio.
defaultPref("media.autoplay.blocking_policy", 2);

// Ask before allowing WebGL instead of silently permitting it.
defaultPref("librewolf.webgl.prompt", true);
defaultPref("librewolf.webgl.prompt.hide", false);

// Extension firewall: deny extensions any remote code or network fetch.
// NOTE: this stops uBlock Origin from updating its filter lists.
defaultPref("extensions.webextensions.base-content-security-policy",
            "default-src 'none'; script-src 'none'; object-src 'none';");
defaultPref("extensions.webextensions.base-content-security-policy.v3",
            "default-src 'none'; script-src 'none'; object-src 'none';");
```

> **Three things not to do.** Don't re-enable Google Safe Browsing (it is a
> lookup service that sees your browsing). Don't set
> `privacy.resistFingerprinting` to `false` to fix a rendering annoyance — that
> throws away the single most valuable protection LibreWolf gives you. Don't
> relax `security.OCSP.require`; hard-fail is the point.

> **Why there's no `user.js` section here.** The well-known hardened `user.js`
> sets (arkenfox and its derivatives) are written for desktop Firefox, and
> arkenfox's own README warns that applying them as-is to other Gecko browsers
> "can be counterproductive" — LibreWolf already sets many of the same prefs,
> and the two fight. Deeper per-pref tuning belongs in your dotfiles alongside
> the overrides file.

### 10. Application sandboxing + firecfg

Firejail and Bubblewrap were both pacstrap'd. `firecfg` symlinks every installed
program that ships a Firejail profile into `/usr/local/bin`, so `ghostty`,
`librewolf`, etc. auto-launch sandboxed. Profiles live in
`/etc/firejail/*.profile`; per-user overrides in `~/.config/firejail/`.

Run `firecfg` now that the desktop apps (LibreWolf above) are
installed:

```bash
sudo firecfg
```

> Re-run `sudo firecfg` any time you install a new GUI app you want
> auto-sandboxed.

Bubblewrap (`bwrap`) is for one-off, tighter jails — e.g. run an untrusted build
with no network and a read-only root:

```bash
bwrap --ro-bind / / --dev /dev --unshare-all --new-session ./suspicious-binary
```

### 11. Install your dotfiles

Every user-level config from here on — the Sway config, the (empty) Quickshell
shell, zsh, ghostty, git, tmux, and the rest — lives in one dotfiles repo. Clone
it and run the install script; it symlinks each tool's directory into
`~/.config/` and drops `~/.zshenv` in place:

```bash
mkdir -p ~/projects
git clone git@github.com:philipp-bliznuk/arch-btw.git ~/projects/dotfiles
cd ~/projects/dotfiles
./install.sh

# Creates ~/Documents, ~/Downloads, ~/Pictures, … and ~/.config/user-dirs.dirs
xdg-user-dirs-update
```

> **Cloning over SSH needs your key first.** The `git@github.com:` URL
> authenticates with the SSH key from your YubiKey (Step 10) or an on-disk key.
> If you haven't wired that up yet, clone over HTTPS
> (`https://github.com/philipp-bliznuk/arch-btw.git`) for now and switch the
> remote later.

> **What `install.sh` does — and only that.** It creates symlinks, nothing else.
> Each package directory (`sway`, `quickshell`, `zsh`, `ghostty`, `git`, `tmux`,
> `bat`, `nvim`, `yazi`, …) is linked to `~/.config/<name>`; `zsh/.zshenv` is the
> single file linked into `$HOME` (it bootstraps `ZDOTDIR=~/.config/zsh`, so the
> login files `.zprofile`/`.zshrc` are read from there). It does **not** install
> packages, apply themes, or restart services — packages are this guide's job,
> theming is hardcoded in each config.

> `xdg-user-dirs` is installed but does nothing until `xdg-user-dirs-update` is
> run once as your user. Skip it and GTK file pickers, portal save dialogs, and
> screenshot targets all fall back to `$HOME`.

**The Sway config it symlinks** (`~/.config/sway/config`) is a scaffold derived
from the stock `/etc/sway/config`, with the edits this setup relies on already
applied. You don't hand-edit the stock file; the notes below explain *why* the
shipped config looks the way it does, so you can extend it later:

```
# `$term` points at ghostty; `$menu` toggles the Quickshell launcher. The exact
# IPC command depends on your shell config; a common pattern is
# `qs ipc call launcher toggle`. Until your QML defines that IPC handler, the
# bind does nothing.
set $term ghostty
set $menu qs ipc call launcher toggle

# Keyboard layout for the Wayland session.
input * {
    xkb_layout "us"
}

# Launch Quickshell (bar + launcher + notifications + wallpaper).
exec quickshell

# Volume/mute via wireplumber.
bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0
bindsym --locked XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym --locked XF86AudioMute        exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym --locked XF86AudioMicMute     exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# Idle ladder.
exec swayidle -w \
    timeout 900  'pgrep -x swaylock || swaylock -f' \
    timeout 905  'swaymsg "output * power off"' \
         resume  'swaymsg "output * power on"' \
    timeout 1800 'systemctl suspend-then-hibernate' \
    before-sleep 'pgrep -x swaylock || swaylock -f'

# Screenshot region to ~/Pictures.
bindsym Print exec grim -g "$(slurp)" ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png
```

> **No stock `bar { ... }` block.** Quickshell draws its own top bar as a
> `wlr-layer-shell` surface, so the shipped config leaves Sway's bar out
> entirely. Don't add one: a `bar` block with no id spawns swaybar, and you'd end
> up running swaybar *and* the Quickshell bar side by side. The volume binds use
> `wpctl`, not the stock `pactl` ones.
>
> **No `output * bg` line.** `swaybg` is not installed — Quickshell paints the
> wallpaper. A stock `output * bg ...` line would fail (`swaybg` missing) and log
> an error on every start. Set the wallpaper in your Quickshell config instead.
>
> **`include /etc/sway/config.d/*` stays.** It's not decoration: it pulls in
> sway's `50-systemd-user.conf`, which exports the session's environment into the
> systemd user session and D-Bus. `xdg-desktop-portal-wlr` needs that, so
> dropping the line breaks screen sharing and screen capture in a way that looks
> like a portal bug.

> **`KEYMAP=us` in Step 4 does not cover this.** `/etc/vconsole.conf` sets the
> layout for the text consoles only. Sway reads its keyboard layout from its own
> `input` block via xkb, so without the block above a non-US layout works at the
> LUKS/TTY prompt and then reverts to US the moment Sway starts. Replace `"us"`
> with your layout (`de`, `fr`, `gb`, …); `xkb_variant` and `xkb_options` go in
> the same block.

> **Volume via `wpctl`, not `pactl`.** `wpctl` ships with wireplumber, which is
> already running the session — no PulseAudio compatibility layer in the path.
> `-l 1.0` caps volume at 100 % (`wpctl` will happily amplify past that).
> `pactl` would also work, since `libpulse` comes in as a dependency of
> `pipewire-pulse`, but there is no reason to route through it.
>
> `--locked` is what allows the binding to fire while `swaylock` is up. Without
> it, volume and mute go dead the moment the screen locks. Sway's stock
> `brightnessctl` and `playerctl` binds already carry the flag — keep it on
> anything you'd want to reach without unlocking.

> **The idle ladder.** 15 min → lock, +5 s → screens off, 30 min → suspend to
> RAM, then roughly an hour later (or below 5 % battery, whichever comes first)
> → hibernate to disk. The `before-sleep` hook is what keeps the session locked
> across a sleep: without it the machine wakes straight back into your desktop.
> `swayidle -w` holds the systemd sleep inhibitor until `swaylock` is actually
> up, so there is no window where the unlocked screen is visible. The
> `pgrep -x swaylock ||` guard stops a second lock instance spawning when the
> screen is already locked. Note that swayidle is session-scoped — no Sway
> session means no idle actions, which is why a bare TTY or an SSH-only login
> never sleeps on its own. Timings live in your dotfiles; tune them there.

### 12. Audio

PipeWire is socket-activated; it starts on demand inside your Sway session — no
manual enable needed.

### 13. Start Sway

Auto-starting Sway on TTY1 login (no display manager) is already wired up by the
dotfiles: `~/.config/zsh/.zprofile` (symlinked in Step 8 #11) runs `exec sway`
when you log in on TTY1, and `~/.local/bin` is on `PATH` via `~/.zshenv`. Because
`.zshenv` sets `ZDOTDIR=~/.config/zsh`, zsh reads that `.zprofile` on login —
there is nothing to write by hand:

```sh
# ~/.config/zsh/.zprofile (installed, shown for reference)
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
    exec sway
fi
```

**Now move to the machine itself.** Sway needs a real local seat — it cannot
start over SSH, so this is where the remote half of the install ends. Close the
SSH session, go to the laptop, and log in as `<yourname>` on TTY1.

That login *is* the test: `.zprofile` fires `exec sway` automatically. If Sway
comes up, you're done. If you land back at a shell prompt instead, run it by hand
to read the error:

```bash
sway
```

Common causes are a typo in `~/.config/sway/config`, a missing GPU driver, or a
seat/permission problem — see [Troubleshooting](#sway-wont-start-on-login) and
[seat errors](#sway-exits-immediately-with-a-seat-or-permission-error).

> **Optional — autologin.** Only enable this **after** you've confirmed Sway
> starts cleanly above. With autologin, a Sway that fails to launch turns into a
> silent relogin loop with no prompt to debug from:
>
> ```bash
> sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
> sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
> [Service]
> ExecStart=
> ExecStart=-/usr/bin/agetty --autologin <yourname> --noclear %I $TERM
> EOF
> ```
>
> Full boot flow with autologin:
> LUKS passphrase (or YubiKey touch) → boot → TTY1 auto-login → Sway.

### 14. Close the remote-access door

You're on the machine now, so the SSH path that carried the install is dead
weight. From a terminal inside Sway:

```bash
sudo systemctl disable --now sshd
sudo ufw delete limit ssh
```

Confirm nothing is listening and the rule is gone:

```bash
ss -tlnp | grep :22   # should print nothing
sudo ufw status
```

> **Why turn it off.** `sshd` was enabled back in Step 5 for exactly one reason:
> so Step 8 could be driven over SSH from another machine. On a single-user
> laptop a permanently listening service reachable with a password is the one
> component that contradicts the rest of this build.
>
> If you do want remote access later, re-enable it **key-only** rather than as
> shipped:
>
> ```bash
> sudo mkdir -p /etc/ssh/sshd_config.d
> sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
> PasswordAuthentication no
> KbdInteractiveAuthentication no
> PermitRootLogin no
> AllowUsers <yourname>
> EOF
> sudo systemctl enable --now sshd
> sudo ufw limit ssh
> ```
>
> Put your public key in `~/.ssh/authorized_keys` **before** enabling that — with
> `PasswordAuthentication no` and no key on file you lock yourself out of the
> remote path entirely (local login still works).

From this point, every `yay` or `pacman` transaction creates pre/post snapshots
via `snap-pac`. `sdboot-snaps` watches `/.snapshots` and builds a self-contained
UKI for each snapshot (each embeds its own `rootflags=subvol=...`), dropping it
in `/boot/efi/EFI/Linux/`. systemd-boot auto-discovers these entries.

**Recovery flow after a bad update:**

1. Reboot → hold Space → select the pre-update snapshot from the menu.
2. You boot straight into it — fully functional and **writable**. This gets you
   working again immediately, but it's temporary: the default boot target is
   unchanged, so a plain reboot returns to the broken state.
3. Once confirmed good, make it permanent with `sudo btrfs-assistant`
   (Snapshots → select → Restore). On the Arch layout it swaps the running `@`
   for a fresh read-write copy of the snapshot (old `@` kept as backup), so the
   `rootflags=subvol=@` cmdline keeps working unchanged.
4. Reboot normally — the restored state is now your live system.

> **Why not `snapper rollback`?** That command assumes the openSUSE subvolume
> layout. On the "Arch" layout used here (`@`, `@home`, `@snapshots`),
> `btrfs-assistant` is the correct tool. The AUR package `snapper-rollback` is
> a CLI-only alternative if you prefer.

---

## Step 9 — (Optional) Secure Boot

This is **not redundant with the UKI.** A UKI is _packaging_ — it bundles the
kernel, initramfs, and cmdline into one signable `.efi` — but the firmware will
still happily boot an unsigned or tampered UKI on its own. Secure Boot is the
_enforcement_ layer: the firmware checks each `.efi` against keys you enrolled
and refuses anything you didn't sign. UKI makes the boot image signable; Secure
Boot is what actually gives it teeth.

Skip this on a desktop if you're not concerned about physical access attacks.

> **No TPM required.** This is key-based Secure Boot: the firmware checks each
> `.efi` against keys you enroll into UEFI, which is pure UEFI key storage — no
> TPM involved. A TPM only matters for _different_ features this guide doesn't
> use (TPM-sealed LUKS unlock or measured-boot attestation); your disk is
> unlocked by FIDO2 + passphrase instead, so Secure Boot works fine with the TPM
> absent or disabled.
>
> **Firmware prerequisites.** The machine must be booted in **UEFI mode, not
> Legacy/CSM** (the whole ESP + systemd-boot + UKI stack is UEFI-only; a new
> laptop is almost always UEFI by default — just confirm CSM is off). That is the
> only firmware setting beyond entering Setup Mode below.

```bash
# 1. Put the firmware in Setup Mode
#    Reboot → enter UEFI firmware setup (F2/F10/F12/Del at power-on, varies)
#    → Security (or Boot) → find the Secure Boot key options and choose
#      "Clear/Delete/Erase all Secure Boot keys" (a.k.a. reset to Setup Mode)
#    → save & exit, boot back into the system
#    Confirm you are in Setup Mode:
sudo sbctl status                    # should report: Setup Mode: Enabled

# 2. Create and enroll your own keys
sudo sbctl create-keys
# If enroll-keys fails with "File is immutable", run:
#   sudo chattr -i /sys/firmware/efi/efivars/{KEK,db,PK}-*
# then retry the enroll command.
sudo sbctl enroll-keys --microsoft   # also enrolls Microsoft's keys so signed
                                     # option ROMs (GPUs/NICs) and any dual-boot
                                     # Windows still validate

# 3. Sign the UKIs and bootloader
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-fallback.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-lts.efi
sudo sbctl sign -s /boot/efi/EFI/Linux/arch-linux-lts-fallback.efi
sudo sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/efi/EFI/BOOT/BOOTX64.EFI

# 4. Sign the bootloader at its SOURCE too — see the note below
sudo sbctl sign -s \
  -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
     /usr/lib/systemd/boot/efi/systemd-bootx64.efi

# 5. Verify — all files should show ✓
sudo sbctl verify

# 6. Re-enable Secure Boot
#    Reboot → UEFI firmware setup → Security → set Secure Boot to Enabled
#    → save & exit. The firmware now enforces your signatures.
```

> Every `sbctl` call needs root: it reads and writes UEFI variables under
> `/sys/firmware/efi/efivars/` and signs files on the ESP.

> **Why step 4 exists.** `bootctl install` enabled `systemd-boot-update.service`,
> which copies a new bootloader to the ESP on the **next boot** — that is, *after*
> the `sbctl` pacman hook has already run. So a plain systemd upgrade would leave
> an **unsigned** `systemd-bootx64.efi` on your ESP and the firmware would refuse
> to boot it. Signing the source copy sidesteps this: `bootctl` prefers a
> `.efi.signed` file over the plain `.efi` when one exists, so what lands on the
> ESP is already signed. Re-run that one command after a systemd upgrade if you
> ever see `sbctl verify` flag the bootloader.

> The `zz-sbctl.hook` pacman hook ships with `sbctl` and re-signs UKIs
> automatically on every kernel or systemd upgrade. Nothing manual needed
> day-to-day.
>
> **sdboot-snaps**: set `SBCTL=true` in `/etc/sdboot-snaps.conf` so snapshot
> UKIs are signed automatically too.

---

## Step 10 — (Optional) Wire Up Hardware Keys: GPG + SSH

> **Doing this on macOS instead?** [YUBIKEY.md](./YUBIKEY.md) covers the same
> GPG/SSH provisioning from scratch on a Mac, including the two-key clone. This
> section is the on-Linux equivalent.

This wires an **already-provisioned** GPG identity into this Arch machine —
smartcard daemon, SSH-through-gpg-agent, and Git commit signing. It assumes you
followed [YUBIKEY.md](./YUBIKEY.md) first, so both YubiKeys already carry the
same three subkeys (Sign / Encrypt / Authenticate), the OpenPGP applet is
hardened (KDF on, PINs changed, 8/8/8 retries, per-operation touch), and you
have `public.asc` from that backup. Nothing here is required for a working
system; it's the top layer of the security chain.

> **Haven't provisioned the keys yet?** Do it once, on any machine, following
> [YUBIKEY.md](./YUBIKEY.md) — it covers key generation, the offline backup, and
> cloning both cards in full. That guide is the single source of truth for
> _creating_ the identity; this section only _connects_ it to Arch. Don't
> generate a second, different key here.

> **Best done locally from a Sway terminal — not over SSH.** Card operations
> trigger PIN prompts via `pinentry-curses`. Over SSH this works _if_ you first
> run `export GPG_TTY=$(tty)` and `gpg-connect-agent updatestartuptty /bye`, and
> **avoid `ssh -A`** (agent forwarding collides with the gpg-agent SSH socket).
> Easier to just do it locally once you have Sway running.

### 1. Smartcard daemon

Already handled if you did Step 8 #7. Otherwise:

```bash
sudo systemctl enable --now pcscd.socket
```

### 2. Let GnuPG share the device

Without this, `scdaemon` grabs the YubiKey exclusively and `ykman` (and card
swaps) break:

```bash
mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
cat > ~/.gnupg/scdaemon.conf <<'EOF'
disable-ccid
pcsc-shared
EOF
```

### 3. Import your public key and trust it

The private subkeys already live on the cards; this machine only needs the
**public** key (and its ownertrust) to know the identity. Copy `public.asc` and
`ownertrust.txt` from your YUBIKEY.md backup, then:

```bash
gpg --import public.asc
gpg --import-ownertrust ownertrust.txt
# Confirm the card is seen and the stubs bind to it:
gpg --card-status
```

> `gpg --card-status` with a key inserted creates the on-disk **stubs** that
> point at the card serial — GnuPG needs these to route signing/auth to the
> hardware. Insert either YubiKey; both carry the same subkeys.

### 4. gpg-agent: pinentry, SSH support, 1-week PIN cache

```bash
cat > ~/.gnupg/gpg-agent.conf <<'EOF'
pinentry-program /usr/bin/pinentry-curses
enable-ssh-support
default-cache-ttl 604800
max-cache-ttl 604800
EOF
gpgconf --kill gpg-agent
```

Add to `~/.zshrc` so SSH uses the GPG agent:

```zsh
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
gpg-connect-agent updatestartuptty /bye >/dev/null
```

> Put these in `~/.zshrc`, **not** `.zprofile` — the login `.zprofile`
> ends with `exec sway`, which replaces the shell and never returns, so
> anything appended below it never runs. `~/.zshrc` is sourced by every
> interactive shell inside the session, which is where you need the agent
> socket live.

The one-week `max-cache-ttl` means you enter the OpenPGP PIN roughly once a week;
every individual signing/auth operation still requires a physical touch.

### 5. Wire up Git commit signing

List the subkeys with `gpg --list-secret-keys --keyid-format long` (they show as
`ssb>` = on-card stub). Find the one with `usage: S` — that's your signing
subkey ID.

```bash
git config --global user.signingkey <signing-subkey-id>!
git config --global commit.gpgsign true
git config --global gpg.format openpgp
```

Upload the **public** key to GitHub (Settings → SSH and GPG keys). Use the
**primary** key ID for the export (GitHub extracts all subkeys from it):

```bash
gpg --armor --export <key-id>
```

The trailing `!` pins Git to the signing subkey specifically. Signing a commit
now prompts for a YubiKey touch (PIN once per cache window).

> **Multiple GitHub accounts?** The GPG signing key can be uploaded to all of
> them — no restriction. The SSH auth key (next section) is one-account-only on
> GitHub; for other accounts use HTTPS or a deploy key. The signing flow
> (this section's goal) is unaffected.

### 6. SSH from the GPG auth subkey

The auth subkey already acts as your SSH identity via the agent. Grab the public
key and add it to GitHub / remote hosts:

```bash
ssh-add -L        # prints the ssh-ed25519 line backed by the card
```

> If `ssh-add -L` prints nothing, the agent hasn't picked up SSH support yet.
> Re-log in (or run `gpg-connect-agent updatestartuptty /bye`) with a card
> inserted, then retry.

> **Card swap.** After physically switching keys, tell the agent to re-read the
> new card: `gpg-connect-agent "scd serialno" "learn --force" /bye`.

---

## Credentials Reference

Five independent credentials govern this system. They share no material:
| # | Credential | Where | Purpose | Set/Change |
|---|-----------|-------|---------|------------|
| 1 | LUKS passphrase | LUKS keyslot 0 | Disk unlock (fallback) | `cryptsetup luksChangeKey /dev/sda2` |
| 2 | FIDO2 touch | YubiKey FIDO2 applet | Disk unlock (primary, if enrolled) | touch-only (no PIN with `--fido2-with-client-pin=no`) |
| 3 | OpenPGP user PIN | YubiKey OpenPGP applet | GPG sign/decrypt/auth daily | `gpg --card-edit` → `admin` → `passwd` opt 1 (factory `123456`; changed in YUBIKEY.md) |
| 4 | OpenPGP admin PIN | YubiKey OpenPGP applet | Provisioning: keytocard, set-touch, change PINs | `gpg --card-edit` → `admin` → `passwd` opt 3 (factory `12345678`; changed in YUBIKEY.md) |
| 5 | Login password | `/etc/shadow` | TTY/SSH login, sudo | `passwd` |

> **FIDO2 applet ≠ OpenPGP applet.** They are independent credential stores on
> the same physical key. The FIDO2 PIN (if set) has only 8 attempts total; a
> blocked PIN requires `ykman fido reset` (wipes the FIDO2 applet). The OpenPGP
> admin PIN allows 3 attempts by default, or 8 if you provisioned the keys per
> [YUBIKEY.md](./YUBIKEY.md) (`set-retries 8 8 8`); exhausting it requires
> `ykman openpgp reset`. Neither reset touches the other applet.
>
> `/dev/sda2` in the commands above and in Troubleshooting is an example — the
> installed system may name the disk differently from the live ISO. Confirm the
> `crypto_LUKS` partition with `lsblk -f` before running anything against it.

---

## Day-to-Day Reference

| Task                                | Command                                                            |
| ----------------------------------- | ------------------------------------------------------------------ |
| Update system (auto-snapshots)      | `yay`                                                              |
| Manual snapshot before risky change | `snapper -c root create --description "before X"`                  |
| List snapshots                      | `snapper -c root list`                                             |
| Roll back (temporary)               | Reboot → hold Space → select snapshot from menu                    |
| Roll back (make permanent)          | `sudo btrfs-assistant` → Snapshots → Restore                       |
| Boot recovery kernel                | Reboot → hold Space → pick `linux-lts` UKI                         |
| Launch terminal                     | `Super+Return` (ghostty)                                           |
| App launcher / calculator           | `Super+D` (Quickshell launcher)                                   |
| Restart the shell (bar/launcher)    | `pkill quickshell; quickshell &` — the compositor keeps running   |
| Browse the web (sandboxed)          | `librewolf`                                                        |
| Lock screen                         | `swaylock` (auto after 15 min idle via swayidle)                   |
| Sleep now (RAM, then disk)          | `systemctl suspend-then-hibernate` (auto after 30 min idle)        |
| Hibernate (suspend to disk)         | `systemctl hibernate`                                              |
| Screenshot (region)                 | `Print` → `grim -g "$(slurp)"`                                     |
| Sandbox a GUI app                   | Auto via Firejail (`firecfg` done); or `firejail <app>`            |
| Sandbox an untrusted command        | `bwrap --ro-bind / / --dev /dev --unshare-all --new-session <cmd>` |
| Check boot entries                  | `bootctl list`                                                     |
| Check systemd-boot status           | `bootctl status`                                                   |
| Connect to Wi-Fi                    | `nmcli device wifi connect "<SSID>" password "<password>"`                   |
| Unlock disk with YubiKey            | Touch key at boot (passphrase fallback)                            |
| Login / sudo with YubiKey           | Touch either key (password fallback)                               |
| Sign a Git commit                   | `git commit -S` → touch key (PIN once per week)                    |
| Switch to the other YubiKey         | `gpg-connect-agent "scd serialno" "learn --force" /bye`            |
| Back up the LUKS header             | `sudo cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file /tmp/luks-header.img` (then copy off-machine) |

---

## Troubleshooting

### LUKS unlock hangs or times out

**Cause**: Mixed mkinitcpio hook families. `systemd` + `encrypt` (busybox) are
incompatible. The `encrypt` hook only works with `udev`; the `systemd` hook
requires `sd-encrypt`.

**Fix**: Ensure the HOOKS line uses one family consistently:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

Then regenerate: `mkinitcpio -p linux`.

---

### sd-vconsole errors during boot

**Cause**: `/etc/vconsole.conf` doesn't exist. The `sd-vconsole` hook requires
it.

**Fix**: `echo "KEYMAP=us" > /etc/vconsole.conf` — then regenerate the UKI.

> Also critical for the LUKS prompt: a missing keymap can make your passphrase
> appear wrong.

---

### Machine doesn't boot after install

**Cause**: No UEFI NVRAM boot entry was created. If you used plain
`arch-chroot`, modern systemd (v257+) treats its PID namespace as a container
and `bootctl install` silently skips the firmware entry — the loader files land
on the ESP but the firmware doesn't know to look for them. On a single-OS
machine the removable fallback `EFI/BOOT/BOOTX64.EFI` usually still boots; a
dual-boot machine (Windows entry takes priority) will not.

**Prevention**: Chroot with `arch-chroot -S` (already covered in Step 3). If you
didn't, create the entry manually:

```bash
# From the live ISO — unlock and mount:
cryptsetup open ${DISK}2 cryptroot
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mount ${DISK}1 /mnt/boot/efi

# Create the NVRAM entry manually:
efibootmgr --create --disk $DISK --part 1 \
    --label "Linux Boot Manager" \
    --loader '\EFI\systemd\systemd-bootx64.efi'
```

---

### Snapper fails with D-Bus error in chroot

**Cause**: `snapper create-config` needs D-Bus and snapperd, which aren't
running in a chroot.

**Fix**: Only enable the timers in chroot. Run the full snapper setup after
the first native boot (Step 8).

---

### mkinitcpio fails with "must be readable"

**Cause**: Running `mkinitcpio -p linux` from the live ISO shell instead of
inside the chroot.

**Fix**: Make sure you're inside `arch-chroot -S /mnt` before running mkinitcpio.

---

### qat_6xxx firmware warning during boot

**Cause**: The kernel tries to load Intel QuickAssist firmware, but the
hardware isn't present.

**Fix**: Harmless. Ignore it.

---

### pacstrap ends with "fatal library error, lookup self"

**Cause**: gpgme agent-cleanup noise printed by the live ISO's package manager at
the end of pacstrap. Has nothing to do with the packages you just installed.

**Fix**: Harmless. Ignore it — your install is fine.

---

### mkinitcpio prints "Secureboot key directory doesn't exist, not signing!"

**Cause**: `sbctl` (installed in Step 3) ships a `mkinitcpio` post hook that tries
to sign every image it builds. Your Secure Boot keys don't exist yet — Step 9
creates them, and Step 9 is optional. The hook detects that and skips signing.

**Fix**: Nothing. The message is informational, the hook exits cleanly, and the
UKIs are built correctly. If you later do Step 9, the hook starts signing
automatically from then on.

> On `sbctl` older than 0.15 this hook tried to sign unconditionally and exited
> **1** instead, which aborted `pacstrap` with
> `error: command failed to execute correctly`. If you hit that on an old ISO,
> either use a current ISO or drop `sbctl` from the `pacstrap` line and install it
> later with `sudo pacman -S sbctl` in Step 9.

---

### `cryptsetup close cryptroot` — "Device or resource busy"

**Cause**: The swapfile activated in Step 4 is still on. An active swapfile pins
the `/dev/mapper/cryptroot` mapping, so `dmsetup info cryptroot` reports
`Open count: 1` and the close fails — even though `umount -R /mnt` succeeded and
`findmnt` is empty.

**Fix**: `swapoff /mnt/swap/swapfile`, then retry `cryptsetup close cryptroot`.

Note that a bare `swapoff -a` from the live shell **will not work here**: it acts
on `/proc/swaps`, where the entry was registered from inside the chroot as
`/swap/swapfile`. That path doesn't exist from the live ISO's root, so `swapoff`
exits 32 and the swap stays active. Step 7 avoids the whole situation by running
`swapoff -a` before leaving the chroot.

If it still refuses, `udevadm settle` and retry; if that fails too, just `reboot`
— the mapping tears down cleanly at power-off and the disk unlocks normally on
the next boot. Don't chase it with `fuser`/`lsof`: they show every kernel PID and
are a red herring.

---

### `sbctl enroll-keys` — "File is immutable"

**Cause**: The EFI variable files in `/sys/firmware/efi/efivars/` have the
immutable attribute set (kernel protection).

**Fix**: `sudo chattr -i /sys/firmware/efi/efivars/{KEK,db,PK}-*` then retry
the enroll command. Confirm `sbctl status` shows "Setup Mode: Enabled" first.

---

### LUKS FIDO2 token fails at boot / PIN blocked

**Cause**: If FIDO2 was enrolled with a PIN (`--fido2-with-client-pin=yes`, the
systemd default), the boot prompt asks for the PIN. Each failed attempt burns
one of only 8 FIDO2 PIN retries. Once blocked, the FIDO2 applet is permanently
locked and no key-based disk unlock is possible until reset.

**Immediate fix**: Skip the FIDO2 prompt — just press Enter/Escape or wait for
timeout, and enter your LUKS passphrase instead (keyslot 0 always works).

**Recovery**: Check `ykman fido info` — if PIN shows "blocked", the only path
is `ykman fido reset` (wipes the FIDO2 applet on that key). Then clear the stale
slots and re-enroll:

```bash
# Removes ALL FIDO2 keyslots — i.e. both YubiKeys, not just the blocked one.
sudo systemd-cryptenroll --wipe-slot=fido2 /dev/sda2

# Re-enroll ONCE PER KEY, swapping the key between runs (same as Step 2).
sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no /dev/sda2
sudo systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no /dev/sda2
```

Confirm you ended up with two tokens again: `sudo cryptsetup luksDump /dev/sda2`.
Replace `/dev/sda2` with your own `crypto_LUKS` partition (`lsblk -f`).

> **FIDO2 reset blast radius.** `ykman fido reset` wipes ONLY the FIDO2/U2F
> applet: LUKS FIDO2 slots (must re-enroll), pam-u2f registration (must re-run
> `pamu2fcfg`), and ALL WebAuthn/passkey website registrations (must re-register
> each site). It does **NOT** touch: OpenPGP applet (GPG keys, PINs — safe), PIV,
> OATH-TOTP (authenticator 6-digit codes — safe), Yubico-OTP/static-password.

**Prevention**: Enroll with `--fido2-with-client-pin=no` (touch-only, no PIN
counter risk). This guide uses that flag in Step 2.

---

### Sway won't start on login

**Cause**: `~/.config/zsh/.zprofile` only launches Sway on TTY1 (`$XDG_VTNR -eq 1`) when no
Wayland session is already running. If you logged in on another VT, or the
compositor exited immediately, you land back at the shell.

**Fix**: Log in on TTY1. Run `sway` manually to read the startup error. Common
causes: a typo in `~/.config/sway/config`, a GPU driver problem (`mesa` is
installed in Step 3 — on proprietary NVIDIA see the driver note in Step 3), or
no seat access (see the next entry).

---

### Sway exits immediately with a seat or permission error

**Cause**: No seat management. Sway needs either `polkit` (via `logind`) or an
enabled `seatd.service` to get access to the GPU and input devices. It also needs
a real local session — starting Sway over SSH will not work.

**Fix**: Confirm `polkit` is installed (`pacman -Q polkit`) and that you're on a
physical VT, then check the session actually has a seat:

```bash
loginctl session-status | grep -i seat
```

If `polkit` isn't an option, use the alternative path instead. `seatd` is already
on the system (it arrives as a `wlroots` dependency), so you only need to turn it
on and join the group: `sudo systemctl enable --now seatd`,
`sudo usermod -aG seat <yourname>`, then log out and back in so the group takes
effect.

---

### Text renders as boxes, or bar icons misalign

**Cause**: Either no font provides the glyph, or `monospace` resolves to the
strict-cell `Mono` variant of the Nerd Font, which clips wide icons.

**Fix**: Check what `monospace` currently resolves to and refresh the cache:

```bash
fc-match monospace
sudo fc-cache -fv
```

It should report `JetBrainsMono Nerd Font`, not `JetBrainsMono Nerd Font Mono`.
If it reports something else, verify `/etc/fonts/local.conf` from Step 5 exists
and that `ttf-jetbrains-mono-nerd` is installed. Missing CJK or emoji glyphs mean
`noto-fonts` / `noto-fonts-emoji` didn't get installed.

---

### An X11-only app won't launch under Sway

**Cause**: The app speaks X11, not Wayland, and Xwayland isn't being invoked.

**Fix**: `xorg-xwayland` is installed and Sway starts it on demand. Verify with
`echo $DISPLAY` inside the session — it should show `:0` (or similar). If empty,
ensure `xwayland enable` is set in the Sway config (it is by default).

---

### Blank session after login — no bar, no wallpaper

**Cause**: Quickshell renders nothing until `~/.config/quickshell/` contains a
QML shell config. A fresh install with empty dotfiles is a black screen with a
working (but invisible) compositor underneath.

**Fix**: Confirm Sway itself is up (`swaymsg -t get_version` in a terminal you
open with `Super+Return`), then put a shell config in `~/.config/quickshell/`
from your dotfiles. Verify Quickshell is running with `pgrep -x quickshell`; if
it isn't, launch it manually with `quickshell` and read the error it prints.

---

### The bar or launcher crashed, but the desktop is still up

**Cause**: Quickshell is pre-1.0. A bad QML reload or a shell bug can take down
the bar/launcher/notification process. Because it's a plain layer-shell client,
this does **not** touch the compositor, your windows, or the lock/idle path.

**Fix**: Restart just the shell without logging out:

```bash
pkill quickshell; quickshell &
```

Nothing else in the session is affected. This crash-tolerance is the reason
`swaylock` and `swayidle` are deliberately kept out of Quickshell.

---

### AppArmor confines an app after enabling

**Cause**: AppArmor may confine an app that lacks a suitable profile.

**Fix**: Check denials with `journalctl -b | grep -i apparmor` or `aa-status`; set
the offending profile to complain mode with `aa-complain /path/to/profile` while
you investigate.

---

### A DKMS module won't load (nvidia, VirtualBox, v4l2loopback…)

**Cause**: On this system as shipped, it shouldn't. Secure Boot (Step 9) validates
the *bootloader and kernel image*, not individual modules, and there is no
`lockdown=` mode in the cmdline — so unsigned DKMS modules load fine. If a module
fails with `ERROR: could not insert module ...: Operation not permitted` or
`Key was rejected by service` while `dkms status` reports `installed`, something
has turned on module signature enforcement.

**Fix**: Check what's enforcing:

```bash
dmesg | grep -iE 'lockdown|module verification|Key was rejected'
cat /sys/kernel/security/lockdown        # should be [none]
cat /sys/module/module/parameters/sig_enforce   # should be N
```

If either shows enforcement, remove `lockdown=<mode>` and/or
`module.sig_enforce=1` from `/etc/cmdline.d/root.conf`, then rebuild both UKIs
(`sudo mkinitcpio -p linux && sudo mkinitcpio -p linux-lts`) and re-sign if
Secure Boot is on (`sudo sbctl sign-all`).

> **Signing the module is not an option here.** Arch's kernels verify module
> signatures against the kernel's own `.builtin_trusted_keys` keyring — *not* the
> UEFI `db` keyring, so `sbctl`'s keys are the wrong keys entirely. The build-time
> signing key is generated per kernel build and discarded, `CONFIG_SYSTEM_TRUSTED_KEYS`
> is empty, and there is no working runtime path to add your own. (There is also no
> `kmodsign` on Arch — that's a Debian patch.) Under enforcement, out-of-tree
> modules are permanently unloadable on a stock kernel: your only choices are
> in-tree drivers, a custom kernel with your key baked in, or no enforcement.
> Every in-repo module is already signed at build time, so a normal system never
> notices any of this.

---

### YubiKey or GPG card not detected

**Cause**: The smartcard daemon isn't running, or `scdaemon` grabbed the device
exclusively.

**Fix**: `sudo systemctl enable --now pcscd.socket`. Confirm `~/.gnupg/scdaemon.conf`
contains `disable-ccid` and `pcsc-shared` (Step 10 #2). Then `gpg --card-status`
should list the card. If it still fails, `gpgconf --kill scdaemon` and retry.

---

### Wrong card serial / Git signing uses the "other" key

**Cause**: `gpg-agent` cached the serial of the card you unplugged, so it keeps
asking for the previous YubiKey.

**Fix**: `gpg-connect-agent "scd serialno" "learn --force" /bye` to re-read the
currently inserted card.

---

### Neither key unlocks the disk

**Cause**: FIDO2 slots weren't enrolled, or the cmdline option is missing.

**Fix**: The passphrase slot always works — enter it at the prompt. Then verify:
`cryptsetup luksDump /dev/sda2` should list `systemd-fido2` tokens, and the UKI
cmdline should contain `rd.luks.options=<UUID>=fido2-device=auto` (Step 5).
Re-enroll with `systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no /dev/sda2`.

---

### Commit signing fails or hangs

**Cause**: No key plugged in, the touch timed out, or the wrong PIN.

**Fix**: Ensure a YubiKey is inserted and touch it when it blinks (default touch
timeout is ~15 s). Check `git config --get user.signingkey` matches your signing
subkey id (with the trailing `!`). `gpg --card-status` confirms the card is seen.

---

### Screen locks but the machine never sleeps

**Cause**: `swayidle` isn't running, or the sleep action itself is failing.

**Fix**: Check the daemon is alive with `pgrep -x swayidle` — a single typo
anywhere in the chain kills the whole `exec` line and you get no idle handling at
all, not even the lock (if the lock works but nothing else does, the typo is
further down the chain). Then trigger the action by hand:

```bash
systemctl suspend-then-hibernate
```

If that fails, the problem is hibernation itself, not the idle timer — see the
two entries below. If it suspends but never flips to disk, confirm the delay
drop-in landed with `systemd-analyze cat-config systemd/sleep.conf` and read
`journalctl -b -u systemd-suspend-then-hibernate`.

Two things that are working as designed and not worth chasing: `swayidle` is
session-scoped, so a bare TTY or an SSH-only login never sleeps on its own; and
`IdleAction=` in `logind.conf` is *not* the mechanism here — logind fires it off
session idle hints and Sway never sets one, so setting it does nothing.

---

### Hibernation refused — "Unable to find a matching swap in /proc/swaps"

**Cause**: systemd can't always compute a Btrfs swapfile's physical offset itself,
so it fails to match `/proc/swaps` against `/sys/power/resume` and
`/sys/power/resume_offset`, and refuses to hibernate. The related message
`Invalid resume config: resume= is not populated yet resume_offset= is` has the
same root cause.

**Fix**: First confirm the basics — swap is at least as large as RAM
(`free -h`, `swapon --show`), `cat /sys/power/resume` is not `0:0`, and the
cmdline made it into the UKI (`cat /proc/cmdline | grep resume`).

If those are all fine, bypass systemd's own memory check. The override must be
present on **both** units:

```bash
sudo systemctl edit --force systemd-logind.service
sudo systemctl edit --force systemd-hibernate.service
```

Add to each:

```
[Service]
Environment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1
```

Then reboot (logind won't pick this up on a reload) and retry
`systemctl hibernate`.

---

### Hibernated fine, but the machine booted fresh instead of resuming

**Cause**: A stale `resume_offset`. The offset is a physical block location — if
the swapfile was ever recreated, resized, moved, or defragmented, the number in
`/etc/cmdline.d/resume.conf` no longer points at it. The kernel finds no valid
image and boots normally, losing the session silently.

**Tell-tales**: `journalctl -b | grep -i swapon` shows
`software suspend data detected. Rewriting the swap signature.`, or
`cat /sys/power/resume` prints `0:0` (the running kernel never learned the resume
device).

**Fix**: Recompute the offset, update the cmdline, rebuild both UKIs, and re-sign
if you enabled Secure Boot:

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
sudo nvim /etc/cmdline.d/resume.conf     # paste the new offset
sudo mkinitcpio -p linux
sudo mkinitcpio -p linux-lts
sudo sbctl sign-all                      # only if Secure Boot is enabled
```

---

## Next Steps

A few things are intentionally left for after the base system is stable. Tackle
them once you're daily-driving comfortably:

**Flesh out the dotfiles.** The repo you cloned in Step 8 #11 already tracks
`~/.config/sway/`, `~/.config/zsh/`, and the rest, so a reinstall is just:
install packages → clone dotfiles → `./install.sh`. The big open item is the
`~/.config/quickshell/` QML shell — the bar, launcher, notification popups, and
wallpaper. Quickshell ships no default UI, so the session stays blank until you
write it; the launcher IPC bind and the `qalc`-backed calculator are yours to
define there too. `librewolf.overrides.cfg` belongs in the same repo. Keep
secrets out of it.

**Podman / dev containers.** Your development environment (containers, language
toolchains, project-specific tooling) lives in your dotfiles repo, not in this
install guide. Add `podman` and friends when you're ready.

**Hardware video acceleration.** `mesa` already provides `libva-driver`, which
covers AMD and older Intel. On newer Intel (Broadwell and later) add
`intel-media-driver` for the iHD VA-API driver; `libva-utils` gives you `vainfo`
to confirm it's picked up. Without it, browser video decodes on the CPU — a
noticeable battery and fan difference on a laptop.

**The application surface.** This guide installs a compositor, a terminal, a
launcher, and a browser — deliberately nothing else. What you actually want on
top is taste, so it belongs in your dotfiles alongside its config: file manager,
image / PDF / video viewer, clipboard history, GTK and Qt theming, cursor theme,
and per-output HiDPI scaling (`output <name> scale 1.5` in the Sway config).
