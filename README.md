# Arch Linux Workstation Install

```
LUKS2 → Btrfs subvolumes → UKI → systemd-boot → snapper + sdboot-snaps → Sway (Wayland) + Quickshell → AppArmor + Firejail + hardened sysctl → YubiKey (FIDO2 + OpenPGP)
```

- `install.sh` — live ISO. Partition, encrypt, pacstrap, base config, FIDO2 LUKS enrollment, clone this repo, reboot. Prompts: disk, timezone, username, three passwords.
- `post-install.sh` — installed system, first boot. Bootloader cleanup, snapper, sdboot-snaps, firewall, YubiKey PAM, dotfiles symlinks, key import, GPG/SSH. Resumable via done-markers.

Prerequisite: both YubiKeys provisioned per [YUBIKEY.md](./YUBIKEY.md) (GPG identity on card, FIDO2 PIN set).

---

## Step 0 — Flash ISO

Download ISO + `sha256sums.txt` from [archlinux.org/download](https://archlinux.org/download/).

```sh
sha256sum archlinux-x86_64.iso        # Linux
shasum -a 256 archlinux-x86_64.iso    # macOS
```

macOS:

```sh
diskutil list                                                         # find USB by size
diskutil unmountDisk /dev/disk4                                       # unmount, not eject
sudo dd if=archlinux-x86_64.iso of=/dev/rdisk4 bs=4m status=progress  # rdisk = raw node; lowercase 4m
diskutil eject /dev/disk4
```

Linux:

```sh
lsblk
sudo umount /dev/sdb*                                                 # "not mounted" is fine
sudo dd if=archlinux-x86_64.iso of=/dev/sdb bs=4M status=progress oflag=sync   # whole device, not sdb1
sync && sudo eject /dev/sdb
```

- macOS `diskutil list` afterwards shows `FDisk_partition_scheme` + small `0xEF` + free space — normal, write succeeded.
- Won't boot: disable Secure Boot in firmware (stays off — this setup doesn't use it), pick the `UEFI:` entry, not Legacy.

---

## Step 1 — `install.sh` (live ISO)

Get online first. Wired = automatic. Wi-Fi:

```bash
iwctl device list                       # station name, e.g. wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "<SSID>"    # prompts passphrase; install.sh copies this profile into the installed system
```

```bash
curl -fsSL https://raw.githubusercontent.com/philipp-bliznuk/arch-btw/master/install.sh -o install.sh
bash install.sh                         # not curl | bash — needs a tty for prompts
```

Prompts, in order: disk (wiped), timezone (`Europe/Berlin`), username, LUKS passphrase, user password, root password (each twice). Summary → type `YES`.

FIDO2 enrollment pauses twice: `Insert YubiKey #1 ONLY, then press Enter`, then key #2.

- Exactly one key inserted per pause (`--fido2-device=auto`).
- Key asks **FIDO2 PIN + touch** despite `--fido2-with-client-pin=no` — CTAP2 credential creation always needs the PIN once. Day-to-day unlock = touch only.
- Enrollment failure → retry prompt, not abort.
- Boot with no key inserted → passphrase prompt. Keyslot 0 always works.

Flags: `--skip-fido2` (VM), `DEBUG=1 bash install.sh` (trace). Re-run after failure re-wipes the disk.

Baked in: `sgdisk` 2G ESP + LUKS2 remainder; Btrfs `@ @home @snapshots @swap` (`noatime,compress=zstd`); hostname `arch-btw`; RAM-sized hibernation swapfile; systemd HOOKS + UKI presets; systemd-boot; hardened sysctl; Quad9 DoT; Cloudflare NTS; journald 200M; lid → suspend-then-hibernate; JetBrainsMono Nerd Font; ucode auto (Intel/AMD); repo cloned to `~/projects/dotfiles`.

---

## Step 2 — `post-install.sh` (first boot)

Unlock, then `Ctrl-Alt-F2` → log in on **TTY2** (TTY1 `exec sway` once dotfiles are linked).

```bash
~/projects/dotfiles/post-install.sh              # run / resume
~/projects/dotfiles/post-install.sh --list       # step status
~/projects/dotfiles/post-install.sh --redo keys  # force one step
```

Runs as user, `sudo` where needed. Markers: `~/.local/state/arch-btw/done/`. Log: `~/.local/state/arch-btw/post-install.log`.

| #   | Step         | Hands-on                                                                                                                                                                                                          |
| --- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | bootloader   | Confirm deleting stale EFI entries (partuuid ≠ current ESP).                                                                                                                                                      |
| 2   | network      | Only if offline — `nmcli … --ask`.                                                                                                                                                                                |
| 3   | snapper      | —                                                                                                                                                                                                                 |
| 4   | luks_header  | Insert + pick USB partition (`s` skips). Backup written to USB only.                                                                                                                                              |
| 5   | sdboot_snaps | —                                                                                                                                                                                                                 |
| 6   | firewall     | —                                                                                                                                                                                                                 |
| 7   | yubikey_pam  | Insert key #1, then key #2 (`pamu2fcfg`). FIDO2 PIN asked once per key (CTAP2). Tests `sudo` at the end; password fallback stays (`sufficient`).                                                                  |
| 8   | librewolf    | —                                                                                                                                                                                                                 |
| 9   | firecfg      | Jails `ssh man wget librewolf`; ssh profile allows the gpg-agent socket.                                                                                                                                          |
| 10  | dotfiles     | —                                                                                                                                                                                                                 |
| 11  | keys         | Insert USB with key material (layout below). Imports GPG public keys + `pb`/`gx` secrets + on-disk SSH keys. Then insert a YubiKey → `gpg --card-status`. Writes fresh `~/.ssh/config`, flips repo remote to SSH. |
| 12  | finish       | —                                                                                                                                                                                                                 |

USB for steps 4 and 11: **FAT/exFAT** (mounted by root; ext4 leaves files unreadable). Layout:

```
keys/gpg/ic/public.asc                                 # YubiKey identity — public only
keys/gpg/pb/public.asc   keys/gpg/pb/secret-keys.asc
keys/gpg/gx/public.asc   keys/gpg/gx/secret-keys.asc
keys/ssh/id_ed25519_pb   keys/ssh/id_ed25519_pb.pub
keys/ssh/id_ed25519_gx   keys/ssh/id_ed25519_gx.pub
```

`ic` = card identity (SSH key exported from card). `pb`/`gx` = on-disk. Git signing config comes from dotfiles `git/{pb,ic,gx}`, not the script.

---

## Step 3 — Autologin

After one clean boot into Sway:

```bash
~/projects/dotfiles/post-install.sh --autologin   # getty@tty1 drop-in; .zprofile execs sway
```

---

## Desktop shell (Sway + Quickshell)

One Quickshell process owns everything except lock/idle (`swaylock`/`swayidle` stay). `sway/config` is the single source of truth for keybindings — the launcher parses it live. Helper scripts live in `bin/` (→ `~/.local/bin`, prefix `qs-`); QML rows are data, `core/Commands.qml` is the only exec path.

```
quickshell/
├── shell.qml          root: services + panel + launcher, IPC targets
├── core/              Color Style Icons Util Commands Toggles SwayState Popups (singletons)
├── ui/                Pill Glyph Stacked Field Slider MenuRow PopupCard
├── panel/             Panel.qml, AudioPopup.qml, widgets/ (Menu Workspaces RunningApps Disk Ram Cpu NetRate Media
│                      ActiveWindow Indicators Tray Mic Volume BluetoothPill Network Battery KeyboardLayout Clock)
├── launcher/          Launcher.qml MenuModel.js AppSearch.js   (apps, system, keybinds, capture, toggle, setup, …)
├── notifications/     org.freedesktop.Notifications daemon (popups + history)
├── polkit/            polkit authentication agent
├── osd/               volume / mic / brightness OSD
├── clipboard/         clipboard history (wl-paste watchers → bin/qs-clipboard-capture)
└── background/        wallpaper layer (symlink ~/.local/state/qs/background)
```

| `bin/`                 | Purpose                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `qs-shell [-q] T FN`   | `qs ipc call` wrapper                                                    |
| `qs-session`           | `start` (sway `exec`), `restart` (`$mod+Shift+r`), `stop`                 |
| `qs-toggle NAME`       | `awake` `nightlight` `dnd` `bar-hidden` — flag files + transient units   |
| `qs-capture MODE`      | `region` `window` `screen` `region-clip` `color`                          |
| `qs-wallpaper`         | `set PATH` `next` `random` `current` `list`                               |
| `qs-notify`            | `notify-send` via `busctl`                                                |
| `qs-select PROMPT …`   | dmenu-style picker using the launcher                                    |
| `qs-clipboard-capture` | internal, `wl-paste --watch` target                                       |

State: `~/.local/state/qs/` (`toggles/`, `notifications.json`, `clipboard.json`, `clipboard-images/`, `background`). Clipboard history skips `x-kde-passwordManagerHint` sources (1Password) — the file is still plaintext, rely on LUKS.

IPC targets: `launcher` (toggle/open/close/select) · `notifications` (toggleDnd/clear/clearHistory/count) · `clipboard` (refresh/clear/count) · `osd` (brightness/volume/mic) · `background` (refresh/current) · `toggles` (refresh) · `polkit` (status) · `shell` (ping).

Lint: `quickshell/lint.sh` (qmllint, must be clean).

---

## Recovery

- Broken boot: systemd-boot menu → older snapshot UKI → **btrfs-assistant → Restore**. Not `snapper rollback` (openSUSE layout).
- Neither key unlocks: boot without key, passphrase (keyslot 0), re-enroll.
