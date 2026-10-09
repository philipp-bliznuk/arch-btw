# Arch Linux Workstation Install

```
LUKS2 → Btrfs subvolumes → UKI → systemd-boot → snapper + sdboot-snaps → Sway (Wayland) + Quickshell → AppArmor + Firejail + hardened sysctl → YubiKey (FIDO2 + OpenPGP)
```

- `install.sh` - live ISO. Partition, encrypt, pacstrap, base config, FIDO2 LUKS enrollment, clone this repo, reboot. Prompts: disk, timezone, username, three passwords.
- `post-install.sh` - installed system, first boot. Bootloader cleanup, snapper, sdboot-snaps, firewall, pacman reboot-required hook, Intel GPU PMU helper, YubiKey PAM, yay (AUR helper for `slack-desktop`, `zoom`; built with `bin/yay-git`, which falls back to the GitHub AUR mirror when aur.archlinux.org is down - `yay-git slack-desktop zoom` works without yay too), LibreWolf (firejail XDG whitelist + overrides), dotfiles symlinks, GTK/Qt theme (adw-gtk3 + qt6ct), key import, GPG/SSH. Resumable via done-markers.

Prerequisite: both YubiKeys provisioned per [YUBIKEY.md](./YUBIKEY.md) (GPG identity on card, FIDO2 PIN set).

---

## Step 0 - Flash ISO

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

- macOS `diskutil list` afterwards shows `FDisk_partition_scheme` + small `0xEF` + free space - normal, write succeeded.
- Won't boot: disable Secure Boot in firmware (stays off - this setup doesn't use it), pick the `UEFI:` entry, not Legacy.

---

## Step 1 - `install.sh` (live ISO)

Get online first. Wired = automatic. Wi-Fi:

```bash
iwctl device list                       # station name, e.g. wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "<SSID>"    # prompts passphrase; install.sh copies this profile into the installed system
```

```bash
curl -fsSL https://raw.githubusercontent.com/philipp-bliznuk/arch-btw/master/install.sh -o install.sh
bash install.sh                         # not curl | bash - needs a tty for prompts
```

Prompts, in order: disk (wiped), timezone (`Europe/Berlin`), username, LUKS passphrase, user password, root password (each twice). Summary → type `YES`.

FIDO2 enrollment pauses twice: `Insert YubiKey #1 ONLY, then press Enter`, then key #2.

- Exactly one key inserted per pause (`--fido2-device=auto`).
- Key asks **FIDO2 PIN + touch** despite `--fido2-with-client-pin=no` - CTAP2 credential creation always needs the PIN once. Day-to-day unlock = touch only.
- Enrollment failure → retry prompt, not abort.
- Boot with no key inserted → passphrase prompt. Keyslot 0 always works.

Flags: `--skip-fido2` (VM), `DEBUG=1 bash install.sh` (trace). Re-run after failure re-wipes the disk.

Baked in: `sgdisk` 2G ESP + LUKS2 remainder; Btrfs `@ @home @snapshots @swap` (`noatime,compress=zstd`); hostname `arch-btw`; RAM-sized hibernation swapfile; systemd HOOKS + UKI presets; systemd-boot; hardened sysctl; Quad9 DoT; Cloudflare NTS; journald 200M; lid → suspend-then-hibernate; JetBrainsMono Nerd Font; ucode auto (Intel/AMD); repo cloned to `~/projects/dotfiles`.

---

## Step 2 - `post-install.sh` (first boot)

Unlock, then `Ctrl-Alt-F2` → log in on **TTY2** (TTY1 `exec sway` once dotfiles are linked).

```bash
~/projects/dotfiles/post-install.sh              # run / resume
~/projects/dotfiles/post-install.sh --list       # step status
~/projects/dotfiles/post-install.sh --redo keys  # force one step
```

Runs as user, `sudo` where needed. Markers: `~/.local/state/arch-btw/done/`. Log: `~/.local/state/arch-btw/post-install.log`.

| #   | Step            | Hands-on                                                                                                                                                                                                          |
| --- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | bootloader      | Confirm deleting stale EFI entries (partuuid ≠ current ESP).                                                                                                                                                      |
| 2   | network         | Only if offline - `nmcli … --ask`.                                                                                                                                                                                |
| 3   | nm_connectivity | -                                                                                                                                                                                                                 |
| 4   | snapper         | -                                                                                                                                                                                                                 |
| 5   | luks_header     | Insert + pick USB partition (`s` skips). Backup written to USB only.                                                                                                                                              |
| 6   | sdboot_snaps    | -                                                                                                                                                                                                                 |
| 7   | firewall        | -                                                                                                                                                                                                                 |
| 8   | pacman_hooks    | -                                                                                                                                                                                                                 |
| 9   | gpu_helper      | -                                                                                                                                                                                                                 |
| 10  | battery_limit   | -                                                                                                                                                                                                                 |
| 11  | yubikey_pam     | Insert key #1, then key #2 (`pamu2fcfg`). FIDO2 PIN asked once per key (CTAP2). Tests `sudo` at the end; password fallback stays (`sufficient`).                                                                  |
| 12  | aur_helper      | -                                                                                                                                                                                                                 |
| 13  | librewolf       | -                                                                                                                                                                                                                 |
| 14  | firecfg         | Jails `ssh man wget librewolf`; ssh profile allows the gpg-agent socket.                                                                                                                                          |
| 15  | dotfiles        | -                                                                                                                                                                                                                 |
| 16  | theme           | -                                                                                                                                                                                                                 |
| 17  | keys            | Insert USB with key material (layout below). Imports GPG public keys + `pb`/`gx` secrets + on-disk SSH keys. Then insert a YubiKey → `gpg --card-status`. Writes fresh `~/.ssh/config`, flips repo remote to SSH. |
| 18  | finish          | -                                                                                                                                                                                                                 |

USB for steps 5 and 17: **FAT/exFAT** (mounted by root; ext4 leaves files unreadable). Layout:

```
keys/gpg/ic/public.asc                                 # YubiKey identity - public only
keys/gpg/pb/public.asc   keys/gpg/pb/secret-keys.asc
keys/gpg/gx/public.asc   keys/gpg/gx/secret-keys.asc
keys/ssh/id_ed25519_pb   keys/ssh/id_ed25519_pb.pub
keys/ssh/id_ed25519_gx   keys/ssh/id_ed25519_gx.pub
```

`ic` = card identity (SSH key exported from card). `pb`/`gx` = on-disk. Git signing config comes from dotfiles `git/{pb,ic,gx}`, not the script.

---

## Step 3 - Autologin

After one clean boot into Sway:

```bash
~/projects/dotfiles/post-install.sh --autologin   # getty@tty1 drop-in; .zprofile execs sway
```

---

## Desktop shell (Sway + Quickshell)

One Quickshell process owns everything except lock/idle (`swaylock`/`swayidle` stay). `sway/config` and `tmux/tmux.conf` stay the single source of truth for keybindings - the launcher parses them live into the Keybindings menu (Sway · Tmux · Launcher · Popups), grouping `h/j/k/l` and `1-0` runs into one row and labelling commands from a table in `MenuModel.js`. Helper scripts live in `bin/` (→ `~/.local/bin`, prefix `qs-`, plus `yay-git`); launcher rows and panel buttons are data, `core/Commands.qml` turns them into processes (`argv`, `term` = kitty window, `task` = `qs-task` floating window that waits for Enter when done).

```
quickshell/
├── shell.qml          root: services + panel + launcher, IPC targets
├── core/              Theme Style Icons Util Commands Toggles SwayState Popups System Metrics Player Weather Sun Power Settings (singletons)
├── ui/                Label Glyph Marquee Segment Tooltip PopupCard PopupHost ListRow Chip Field Slider, KeyModel.js (vim keys)
├── panel/             Panel.qml, AudioPopup.qml, MediaPopup.qml, TrayMenu.qml, widgets/ (Workspaces Disk Ram Cpu Gpu NetRate Media Mode Tray
│                      Weather Indicators Dnd NightLight Volume Network Battery KeyboardLayout Clock)
├── launcher/          Launcher.qml Header.qml MenuModel.js AppSearch.js Usage.js
├── notifications/     org.freedesktop.Notifications daemon (popups + history)
├── polkit/            polkit authentication agent
├── osd/               volume / mic / brightness OSD
├── clipboard/         clipboard history (wl-paste watchers → bin/qs-clipboard-capture)
└── background/        wallpaper layer (symlink ~/.local/state/qs/background)
```

Bar: solid 30px, flat `Segment`s, hidden on fullscreen outputs and by the `bar-hidden` toggle; one `PopupCard` open at a time, hosted in a per-output overlay layer (`PopupHost`; not an xdg popup, so keybinds/IPC can open it; clicking outside closes; the card is placed once on open so label changes never move it). Mouse: left-click on Weather/Network/Battery/Clock opens the popup; Dnd and Night light flip on click; Indicators open the launcher's system/toggle section; workspaces switch on click and wheel; Volume right-click mutes; Night light right-click toggles its automation - those last two are the only segments with a tooltip. Popups carry no on-screen key hints; the key table below is the reference (`Esc`/`q` close everywhere). Resource segments (disk · ram · cpu · gpu · net) and Media/Keyboard sit as plain text, no hover - fed by `core/Metrics` (GPU = `/usr/local/bin/qs-gpu-busy`, an i915-PMU helper built from `bin/src` by `post-install.sh` step `gpu_helper`; falls back to AMD `gpu_busy_percent` or i915 rc6 residency). Tray on every output; left-click activates, middle-click secondary-activates, right-click (or left-click on menu-only items) opens the item's dbusmenu as a popup card (`panel/TrayMenu.qml`, submenus descend in place; each item's layout is fetched once when it appears so the first open is already filled; `noto-fonts-cjk` supplies the glyphs JetBrainsMono lacks) - quickshell is not in QApplication mode, so native menus are unavailable. Volume segment shows output % (dimmed when muted); the audio popup holds out/mic mute buttons, device pickers (shown when more than one sink/source) and one volume row per app (a browser's per-tab streams collapse into one row and move together). Clock (`Wed 30 14:05:09`), volume %, cpu/ram/gpu % and net rates sit at fixed widths measured from a template string (`Segment.labelTemplate` sized for the typical value, percentages right-aligned so a single digit leaves its gap beside the icon; the clock's follows the day's digit count; `NetRate` pads to three digits and floors at `KiB/s`) so redraws never shift the bar. Media title scrolls once every 10 s when it overflows (`ui/Marquee`; longer when one pass takes longer). Battery state is one `core/Power` singleton shared by every output (one udev listener, one low-battery toast, one auto-profile write); it reads plugged/charging state from sysfs (`/sys/class/power_supply/AC/online`, `BAT*/status`) and re-reads on `udevadm monitor` power_supply events (plus one settle read 2 s later: the EC reports `Not charging` for ~1 s after a charge-limit write and resumes silently) and on UPower state changes - no polling - so plug/unplug shows instantly instead of after UPower's debounce (UPower still supplies %, time estimates). `qs-toggle nightlight` kills any stray `wlsunset` before starting/after stopping its own so one instance owns gamma on every output. Night light follows sunset/sunrise from `weather.json` (`core/Sun` wakes only at the next sunrise/sunset/midnight; `nightLightAuto` setting); a manual click holds until the next transition, right-click turns the automation off; without a forecast for today (stale file, no network) the automation turns the night light off. Only periodic work in the shell: `core/Metrics` samples each resource on its own timer (net 2 s, cpu 3 s, gpu 5 s, ram 10 s, `df` 5 min) so the bar reads as independent tickers, `qs-weather` refreshes every 15 min, and the Network popup samples rates every 1.5 s while open. Qt timers run on the monotonic clock and freeze across suspend/hibernate, so swayidle's `after-resume` calls `qs-shell shell resume`, which refetches weather, re-reads the clock in `core/Sun` and drops the stale net-rate sample.

Popups open from the keyboard tmux-style: `$mod+o` enters sway mode `popup`, the bar centre shows `POPUP  m media · a audio · n network · b battery · c calendar · w weather` (`panel/widgets/Mode.qml`, fed by `SwayState.mode`), the next key opens the popup and leaves the mode. `resize` mode shows the same way.

Workspaces: `1` and `4` live on the laptop panel, `2` and `3` on the first external output when one is present (sway moves them back out on plug-in, merges everything onto the laptop on unplug). `assign` rules send Slack → 1, kitty → 2, LibreWolf → 3, Zoom → 4; any other workspace is created on the focused output. Caps Lock is a second `$mod` (`caps:super`), so `Caps+N` switches workspaces one-handed. The workspace segment shows a dot on workspaces that hold windows (from sway's `representation`). `core/SwayState` runs one `swaymsg -m -r -t subscribe '["window","mode","input"]'` and fans out binding mode, xkb layout and window changes (workspace occupancy refresh on new/close/move/floating only, fullscreen probe) - Quickshell's I3 module only forwards workspace/output events.

Reboot required: `core/System.qml` watches `/run/reboot-required` (written by the pacman hook `zz-reboot-required.hook` for kernels/systemd/glibc/mesa/firmware/…, installed by `post-install.sh` step `pacman_hooks`) and checks `/usr/lib/modules/$(uname -r)` once at startup (gone after a kernel upgrade). No polling, no notification: shows ↻ in Indicators and a yellow dot on `Packages`/`Update`/`Reboot` rows until reboot (`/run` is tmpfs).

Theme: Catppuccin Mocha, hardcoded in `core/Theme.qml` (named `Theme`, not `Color` - Qt 6.12 ships a `QtQuick/Color` singleton that shadows a singleton of ours by that name). GTK 3/4 share one `gtk/` dir (→ `~/.config/gtk-3.0` and `gtk-4.0`): `gtk.css` sets the libadwaita named colours, `settings.ini` is the fallback; `adw-gtk3-dark` + dark `color-scheme` + fonts go through `gsettings` in `post-install.sh` step `theme`, because GTK3 on Wayland reads `org.gnome.desktop.interface` and ignores `settings.ini` for those keys. Qt apps (incl. `pinentry-qt`) use `qt6ct/` (Fusion, `colors/catppuccin-mocha.conf`, Adwaita Sans) via `QT_QPA_PLATFORMTHEME=qt6ct` from `zsh/.zprofile`; `qs-session` imports it into the systemd user environment so gpg-agent's pinentry gets it too. Quickshell is unaffected: every text goes through `ui/Label`/`ui/Glyph` with explicit font and colour.

Launcher: command menu - breadcrumb, frecency (`~/.local/state/qs/launcher-usage.json`, keys namespaced per section), wallpaper thumbnail grid, `=expr` calculator. Root search also covers System, Packages, Capture, Toggle, Setup and every Keybindings section (rows show a `↳ Section` crumb); name matches rank above keyword matches, then frecency. Apps lists only explicitly installed packages' desktop entries (`bin/qs-apps`), minus `quickshell/apps-hide` (`C--` on a row blacklists it after confirmation). Packages → `qs-pkg` in a `qs-task` window: fzf pickers for pacman (`alt-b` PKGBUILD), AUR (`yay`, `yay-git` when the AUR is unreachable), remove (`pacman -Rns`), update (`yay -Syu`). Two key modes, shown in the header:

| Mode | Keys |
| --- | --- |
| INSERT (default) | type to filter · `C-n`/`C-p` or `C-j`/`C-k` move · `C-d`/`C-u` half-page · `C-o` clear search · `C-l` descend · `C-h`/Backspace-on-empty back (closes at root) · `C-y` copy row · `C-w` delete word · `C-r` refresh app list · `Left`/`Right` move the caret · `Esc` normal mode |
| NORMAL | `j`/`k` · `gg`/`G` · `h` back / clear search (restores the row you left) · `l` descend · `Enter`/`Space` activate · `y` copy · `p` copy clipboard row + close · `d`/`x` delete (clipboard) · `1-9` jump · `r` refresh app list · `C--` blacklist app · `i` insert · `Esc`/`q` close |
| Popups (`$mod+o` …) | no on-screen legend; `Esc`/`q` close everywhere, arrows/Home/End/PgUp/PgDn too |
| Audio (`$mod+o a`) | `j`/`k` row (out mute → mic mute → out volume → sinks → in volume → sources → apps; device rows only with more than one device) · `h`/`l` ±5 % · `m` mute row · `Enter` mute/pick. App rows drive every stream of that app. |
| Clock (`$mod+o c`) | `h`/`l` month · `j`/`k` year · `t` today. Weeks start Monday, ISO week numbers |
| Battery (`$mod+o b`) | `j`/`k` power profile · `c` charge limit on/off (UPower thresholds 75→80 %, `bin/qs-battery`; `post-install.sh` step `battery_limit` turns it on) · `p` toggle %. Auto power-saver on battery (`powerSaverOnBattery`) |
| Network (`$mod+o n`) | `j`/`k` · `Enter` connect/disconnect (inline PSK, WPA-EAP identity) · `w` Wi-Fi on/off · `r` rescan · captive portal row when NM reports Portal |
| Weather (`$mod+o w`) | current conditions, sunrise/sunset, night-light mode · `e` change city (open-meteo geocoding) · `d` back to IP location · `u` °C/°F · `r` refresh |
| Tray menu (right-click icon) | `j`/`k` row · `l`/`Enter` activate or enter submenu · `h` back (closes at top level). Checked entries show `✓`. |
| Media (`$mod+o m`, `$mod+Shift+p`) | cover · title · artist · album · `p` play-pause · `h`/`l` (or `[`/`]`) prev/next · `j`/`k` volume. Volume is the player's PipeWire stream (matched by process/app name, up to 150 % like the audio popup), falling back to MPRIS (0-100 %). Global: `$mod+p`, `$mod+[`/`]` (OSD toast). MPRIS; prefers Feishin, else the playing player, else the first one. |

| `bin/`                 | Purpose                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `qs-shell [-q] T FN`   | `qs ipc call` wrapper                                                    |
| `qs-quit`              | SIGTERM the focused window's process (`$mod+Ctrl+q`; apps that hide to the tray on `kill` actually exit) |
| `qs-session`           | `start` (sway `exec`), `restart` (`$mod+Shift+r`), `stop`                 |
| `qs-toggle NAME`       | `awake` `nightlight` `dnd` `bar-hidden` - flag files + transient units   |
| `qs-capture MODE`      | `region` `window` `screen` `region-clip` `color`                          |
| `qs-wallpaper`         | `set PATH` `next` `random` `current` `list`                               |
| `qs-notify`            | `notify-send` via `busctl`                                                |
| `qs-weather`           | `refresh` `set CITY` `clear` `status` - open-meteo → `weather.json`        |
| `qs-battery`           | `status` `limit [on\|off]` - UPower charge thresholds (JSON)              |
| `qs-network-status`    | internal, JSON for the network popup (ip/gateway/ping/traffic)             |
| `qs-clipboard-capture` | internal, `wl-paste --watch` target                                       |
| `qs-apps`              | `list` `hide ID` - explicitly installed desktop ids minus `apps-hide`; pacman hook touches `/run/qs-apps-changed` to re-list |
| `qs-task CMD…`         | run CMD in a floating 75 % kitty window, `Done!`/`Failed` + Enter to close |
| `qs-pkg MODE`          | `install` `aur` `remove` `update` `pkgbuild PKG` - fzf package pickers    |
| `qs-wifi-prefer SSID`  | autoconnect-priority 10 for SSID's profile, 0 for other Wi-Fi profiles    |
| `yay-git PKG…`         | build AUR packages from git (AUR, GitHub mirror fallback), AUR deps recursive |

State: `~/.local/state/qs/` (`toggles/`, `settings.json`, `notifications.json`, `clipboard.json`, `clipboard-images/`, `weather.json`, `weather-location.json`, `launcher-usage.json`, `background`). Clipboard history skips `x-kde-passwordManagerHint` sources (1Password) - the file is still plaintext, rely on LUKS.

IPC targets: `launcher` (toggle/open/close) · `popups` (toggle/open/close) · `notifications` (toggleDnd/clear/clearHistory/count/dismissLatest/actionLatest; sway `$mod+Shift+d` / `$mod+Shift+a`) · `clipboard` (refresh/clear/count) · `osd` (brightness/volume/mic/media) · `background` (refresh/current) · `toggles` (refresh) · `polkit` (status) · `shell` (ping/resume).

Lint: `quickshell/lint.sh` (qmllint, must be clean).

---

## Recovery

- Broken boot: systemd-boot menu → older snapshot UKI → **btrfs-assistant → Restore**. Not `snapper rollback` (openSUSE layout).
- Neither key unlocks: boot without key, passphrase (keyslot 0), re-enroll.
