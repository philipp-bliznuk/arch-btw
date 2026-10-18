# Arch Linux Workstation Install

```
LUKS2 (FIDO2 PIN + touch) → Btrfs subvolumes → UKI → systemd-boot → snapper + snap-pac + snap-restore → Sway (Wayland) + Quickshell → AppArmor + Firejail + ufw + hardened sysctl → YubiKey (FIDO2 + OpenPGP)
```

- `install.sh` - live ISO. Partition, encrypt, pacstrap, base config (tty1 runs `login` for your user, so a boot is LUKS, then a YubiKey touch, or the password with the key unplugged), FIDO2 LUKS enrollment, clone this repo, reboot. Prompts: disk, timezone, username, three passwords. Log: `/root/arch-install.log`, copied to `/var/log/arch-install.log` on the installed system. Run from a checkout (`post-install.sh` and `.git` next to it) and it installs that tree instead of cloning `master`.
- `post-install.sh` - installed system, first boot. Bootloader cleanup, snapper limits, pacman reboot-required hook, Intel GPU PMU helper, YubiKey PAM (login, sudo, polkit, lock screen), yay (AUR helper for `slack-desktop`, `zoom`; built with `bin/yay-git`, which falls back to the GitHub AUR mirror when aur.archlinux.org is down - `yay-git slack-desktop zoom` works without yay too), LibreWolf (firejail XDG whitelist + overrides), dotfiles symlinks, GTK/Qt theme (adw-gtk3 + qt6ct), key import, GPG/SSH. Resumable via done-markers.

Prerequisite: both YubiKeys provisioned per [YUBIKEY.md](./YUBIKEY.md) (GPG identity on card, the same FIDO2 PIN set on both).

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

FIDO2 enrollment pauses twice, right after `YES` (disk wiped and LUKS formatted, before pacstrap): `Insert YubiKey #1 ONLY (remove the other), then Enter`, then key #2.

- Exactly one key inserted per pause (`--fido2-device=auto`).
- Each key asks **FIDO2 PIN + touch**. That is the PIN from `ykman fido access change-pin`, not the OpenPGP PIN; the prompt prints the retries left. Three wrong in a row block the applet until replug, eight in total wipe it ([YUBIKEY.md](./YUBIKEY.md#pins)).
- Every boot asks the same PIN + touch (`--fido2-with-client-pin=yes`): laptop and key stolen together stay shut.
- Enrollment failure → retry prompt, not abort.
- Boot with no key inserted → passphrase prompt after 30 s. Keyslot 0 always works.

Flags: `--skip-fido2` (VM), `DEBUG=1 bash install.sh` (trace). Re-run after failure re-wipes the disk.

Baked in: `sgdisk` 2G ESP + LUKS2 remainder; Btrfs `@ @home @snapshots @swap` (`noatime,compress=zstd`); hostname `arch-btw`; RAM-sized hibernation swapfile; systemd HOOKS, two UKIs (`arch-linux.efi`, `arch-linux-lts.efi`; no fallback images: the LTS kernel covers a kernel regression, while both UKIs share `mkinitcpio.conf` and rebuild in the same pacman transaction, so a broken initramfs is the ISO case under Recovery); systemd-boot (`default arch-linux.efi`, `timeout 0` - hold Space at power-on for the menu); ufw on (INPUT DROP, OUTPUT ACCEPT); hardened sysctl; Quad9 DoT; Cloudflare NTS; journald 200M; JetBrainsMono Nerd Font; ucode auto (Intel/AMD); repo cloned to `~/projects/dotfiles`. Lid policy: post-install step `lid`.

---

## Step 2 - `post-install.sh` (first boot)

Unlock, then `Ctrl-Alt-F2` → log in on **TTY2** (TTY1 would `exec sway` once the dotfiles are linked; until step 9 every VT asks the password only).

```bash
~/projects/dotfiles/post-install.sh              # run / resume
~/projects/dotfiles/post-install.sh --list       # step status
~/projects/dotfiles/post-install.sh --redo keys  # force one step
```

Runs as user, `sudo` where needed. Markers: `~/.local/state/arch-btw/done/`. Log: `~/.local/state/arch-btw/post-install.log`.

| #   | Step            | Hands-on |
| --- | --------------- | -------- |
| 1   | bootloader      | Confirm deleting stale EFI entries (partuuid ≠ current ESP). |
| 2   | network         | Only if offline - `nmcli … --ask`. |
| 3   | nm_connectivity | - |
| 4   | snapper         | `root`: snap-pac pre/post pairs (20 kept, 10 flagged important) + 5 hourly / 7 daily timeline; `home`: 5 hourly / 7 daily / 4 weekly. |
| 5   | luks_header     | Insert + pick USB partition (`s` skips). Backup written to USB only (`luks-header-YYYYMMDD.img`); re-take after any keyslot change, a restore brings the old keyslots back. |
| 6   | pacman_hooks    | - |
| 7   | gpu_helper      | - |
| 8   | battery_limit   | - |
| 9   | yubikey_pam     | Insert key #1, then key #2 (`pamu2fcfg`, FIDO2 PIN asked once per key). `pam_u2f` goes `sufficient` ahead of the password into `/etc/pam.d/login` (after `pam_nologin`), `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` only - never `system-auth`, which also serves `sshd` (`su` has its own stack, password too). Its cue reads `Touch the YubiKey, or unplug it and type the password`: while the token waits the tty still echoes, so a password typed then shows in clear and is discarded. Tests `sudo` at the end. `/etc/u2f_mappings` is `0640 root:$USER` so the lock screen can run `pam_u2f` as the user. |
| 10  | lock_pam        | Writes `/etc/pam.d/qs-lock-password` (`pam_unix`, no `nullok`; 2 s delay per wrong attempt, and faillock counts them: three wrong passwords close the password path for 10 min, the YubiKey path stays open) and `qs-lock-u2f` (`pam_u2f` touch only) for the Quickshell lock screen, plus a tmpfiles rule that creates `/run/faillock/$USER` at boot (the user-run stack cannot create it itself). |
| 11  | lid             | Writes `/etc/systemd/logind.conf.d/00-lid.conf`: lid close → suspend-then-hibernate, lock only with an external display attached (`HandleLidSwitchDocked=lock`, relayed by `swayidle lock`); reloads logind. |
| 12  | aur_helper      | Writes `/etc/makepkg.conf.d/nodebug.conf` (`OPTIONS+=(!debug)`: no `-debug` split package from local builds), `rustup default stable` (the package ships only proxies), then `yay-git yay-bin`. |
| 13  | librewolf       | Firejail XDG whitelist, `apparmor` back on (the stock profile ignores it), session-bus access for MPRIS and the desktop portal, + overrides, among them the extension base CSP `script-src 'self' 'wasm-unsafe-eval'; object-src 'self'` (no remote code in extension pages; uBlock Origin's filter-list updates still pass). |
| 14  | firecfg         | Symlinks into `/usr/local/bin` for every installed program firejail has a profile for (`librewolf`, `ssh`, `man`, `ping`, `ffplay`, `pdftotext`, ...; `firecfg --list`), plus a pacman hook that re-runs `firecfg` after every transaction touching `/usr/bin` (AUR installs like slack and zoom get their symlink and fixed `.desktop`). The stock ssh profile whitelists the gpg-agent socket. |
| 15  | dotfiles        | - |
| 16  | theme           | - |
| 17  | keys            | Insert USB with key material (layout below). Imports GPG public keys + `pb`/`gx` secrets + on-disk SSH keys. Then insert a YubiKey → `gpg --card-status`. Writes fresh `~/.ssh/config`, `~/.gnupg/gpg-agent.conf` and `scdaemon.conf` (a `--redo keys` overwrites local edits), flips repo remote to SSH. Enables `pcscd.socket`. gpg-agent runs from gnupg's static user sockets; `SSH_AUTH_SOCK` is that socket's fixed path, set in `zsh/.zshenv`. |
| 18  | finish          | - |

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

## Step 3 - Reboot

Power on → LUKS (YubiKey: FIDO2 PIN + touch; no key: passphrase after 30 s) → TTY1 runs `login` for your user (`getty@tty1` drop-in from `install.sh`; `LOGIN_TIMEOUT 0`, so an unattended prompt does not restart `login` every minute): touch the key while it blinks, or unplug it (or wait the ~29 s) and type the password at `Password:`. The cue says so, because the tty echoes while the token waits: a password typed then shows in clear and is discarded. No autologin, `login` authenticates every time → `zsh/.zprofile` execs Sway. TTY2 keeps the `login:` prompt and stays a shell.

---

## Security model

| State | Opens it | Notes |
| --- | --- | --- |
| Off, hibernated | YubiKey + FIDO2 PIN + touch, or the LUKS passphrase | Device and key together are not enough. Eight wrong PINs wipe the key's FIDO2 applet, the passphrase remains ([YUBIKEY.md](./YUBIKEY.md#recovery)). |
| Locked session (suspend included) | touch of a plugged YubiKey, or password | Touch without PIN is the walk-away trade-off; `idleSuspend` 3600 s → `suspend-then-hibernate`, `HibernateDelaySec=1h`, so an hour later the next wake is a LUKS unlock. faillock: three wrong passwords close the password path for 10 min. |
| `login` (any VT), `sudo`, polkit | touch, or password | `pam_u2f` `sufficient` in `/etc/pam.d/login`, `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` only. A machine left at the prompt with the key plugged in is the same walk-away trade-off as the locked session. faillock does not count the touch path, so a locked-out password still leaves the key. |
| `su`, ssh | password | Neither stack carries `pam_u2f` (`su` has its own, `sshd` uses `system-auth`). `sshd` ships with `openssh` but is never enabled; ufw drops inbound anyway. |

Not covered: Secure Boot stays off, so the ESP (systemd-boot, UKIs) is unsigned and the boot menu's editor stays on for recovery - someone with the device can alter the ESP, but reads nothing from the LUKS volume. Clipboard history is plaintext on disk (LUKS covers it). Firejail confines the browser and a few tools (`firecfg --list`), nothing else; the browser also carries AppArmor's `firejail-default` profile through `/etc/firejail/librewolf.local`, and `xdg-dbus-proxy` is what makes the profiles' session-bus filters real (without it firejail allows the whole bus, with only a warning on stderr).

---

## Desktop shell (Sway + Quickshell)

One Quickshell process owns everything, including the lock screen and the idle ladder (`swaylock` stays installed as the fallback, `swayidle` only bridges logind's Lock and sleep signals). `sway/config` and `tmux/tmux.conf` stay the single source of truth for keybindings - the launcher parses them live into the Keybindings menu (Sway · Tmux · Launcher · Popups), grouping `h/j/k/l` and `1-0` runs into one row and labelling commands from a table in `MenuModel.js`. Helper scripts live in `bin/` (→ `~/.local/bin`, prefix `qs-`, plus `yay-git` and `snap-restore`); launcher rows and panel buttons are data, `core/Commands.qml` turns them into processes (`argv`, `term` = kitty window, `task` = `qs-task` floating window that waits for Enter when done). Every interactive zsh execs into the tmux session `default` (`zsh/.zshrc`; a TTY2 login lands in the same session), except the floating terminal (`$mod+Shift+Return`, started with `NO_TMUX=1`).

```
quickshell/
├── shell.qml          root: services + panel + launcher, IPC targets
├── core/              Theme Style Icons Util Commands Toggles SwayState Popups System Metrics Player Weather Sun Power Settings Lock (singletons)
├── ui/                Label Glyph Marquee Segment Tooltip PopupCard PopupHost ListRow Chip Field Slider, KeyModel.js (vim keys)
├── panel/             Panel.qml, AudioPopup.qml, MediaPopup.qml, TrayMenu.qml, widgets/ (Workspaces Disk Ram Cpu Gpu NetRate Media Mode Tray
│                      Weather Indicators Dnd NightLight Volume Network Battery KeyboardLayout Clock)
├── launcher/          Launcher.qml Header.qml MenuModel.js AppSearch.js Usage.js
├── notifications/     org.freedesktop.Notifications daemon (popups + history)
├── polkit/            polkit authentication agent
├── osd/               volume / mic / brightness OSD
├── clipboard/         clipboard history (wl-paste watchers → bin/qs-clipboard-capture)
├── lock/              Locker (ext-session-lock + PAM), Surface (per-output lock screen), Idle (screensaver / lock / suspend ladder)
└── background/        wallpaper layer (symlink ~/.local/state/qs/background)
```

Bar: solid 30px, flat `Segment`s, hidden on fullscreen outputs and by the `bar-hidden` toggle; one `PopupCard` open at a time, hosted in a per-output overlay layer (`PopupHost`; not an xdg popup, so keybinds/IPC can open it; clicking outside closes; the card is placed once on open so label changes never move it). Mouse: left-click on Weather/Network/Battery/Clock opens the popup; Dnd and Night light flip on click; Indicators open the launcher's system/toggle section; workspaces switch on click (`$mod+N` is the keyboard path; no wheel switching); slider wheel deltas accumulate to whole 120-unit steps (`Util.wheelSteps`), so a touchpad flick is one step, not a burst; Volume right-click mutes; Night light right-click toggles its automation - those last two are the only segments with a tooltip. Popups carry no on-screen key hints; the key table below is the reference (`Esc`/`q` close everywhere). Resource segments (disk · ram · cpu · gpu · net) and Media/Keyboard sit as plain text, no hover - fed by `core/Metrics` (GPU = `/usr/local/bin/qs-gpu-busy`, an i915-PMU helper built from `bin/src` by `post-install.sh` step `gpu_helper`; falls back to AMD `gpu_busy_percent` or i915 rc6 residency). Tray on every output, icons decoded at device pixels (`sourceSize` × `Screen.devicePixelRatio`); left-click activates, middle-click secondary-activates, right-click (or left-click on menu-only items) opens the item's dbusmenu as a popup card (`panel/TrayMenu.qml`, submenus descend in place; each item's layout is fetched once when it appears so the first open is already filled; `noto-fonts-cjk` supplies the glyphs JetBrainsMono lacks) - quickshell is not in QApplication mode, so native menus are unavailable. Volume segment shows output % (dimmed when muted); the audio popup holds out/mic mute buttons, device pickers (shown when more than one sink/source), a live input level inside the INPUT slider (`PwNodePeakMonitor` opens a capture stream on the default source only while the card is open) and one volume row per app (a browser's per-tab streams collapse into one row and move together). Clock (`Wed 30 14:05:09`), volume %, cpu/ram/gpu % and net rates sit at fixed widths measured from a template string (`Segment.labelTemplate` sized for the typical value, percentages right-aligned so a single digit leaves its gap beside the icon; the clock's follows the day's digit count; `NetRate` pads to three digits and floors at `KiB/s`) so redraws never shift the bar. Icons that swap (volume level, mic, Wi-Fi strength, battery step, weather, play/pause) sit in a slot as wide as the widest glyph of their family (`Segment.iconAlternatives` → `Glyph.alternatives`, measured by ink via `TextMetrics.tightBoundingRect`); the OSD does the same for its icon and sizes its value column from `100%`/`Mic muted`. Media title scrolls once every 10 s when it overflows (`ui/Marquee`; longer when one pass takes longer). Battery state is one `core/Power` singleton shared by every output (one udev listener, one low-battery toast (its last level sits in `PersistentProperties`, so a config reload does not repeat it), one auto-profile write); it reads plugged/charging state from sysfs (`/sys/class/power_supply/AC/online`, `BAT*/status`) and re-reads on `udevadm monitor` power_supply events (plus one settle read 2 s later: the EC reports `Not charging` for ~1 s after a charge-limit write and resumes silently) and on UPower state changes - no polling - so plug/unplug shows instantly instead of after UPower's debounce (UPower still supplies %, time estimates). `qs-toggle nightlight` kills any stray `wlsunset` before starting/after stopping its own so one instance owns gamma on every output. Night light follows sunset/sunrise from `weather.json` (`core/Sun` wakes only at the next sunrise/sunset/midnight; `nightLightAuto` setting); a manual click holds until the next transition, right-click turns the automation off; without a forecast for today (stale file, no network) the automation turns the night light off. Only periodic work in the shell: `core/Metrics` samples each resource on its own timer (net 2 s, cpu 3 s, gpu 5 s, ram 10 s, `df` 5 min) so the bar reads as independent tickers, `qs-weather` refreshes every 15 min, and the Network popup samples rates every 1.5 s while open. Qt timers run on the monotonic clock and freeze across suspend/hibernate, so swayidle's `after-resume` calls `qs-shell shell resume`, which refetches weather, re-reads the clock in `core/Sun` and drops the stale net-rate sample.

Popups open from the keyboard tmux-style: `$mod+o` enters sway mode `popup`, the bar centre shows `POPUP  m media · a audio · n network · b battery · c calendar · w weather` (`panel/widgets/Mode.qml`, fed by `SwayState.mode`), the next key opens the popup and leaves the mode. `resize` mode shows the same way.

Workspaces: `1` and `4` live on the laptop panel, `2` and `3` on the first external output when one is present (sway moves them back out on plug-in, merges everything onto the laptop on unplug). `assign` rules send Slack → 1, kitty → 2, LibreWolf → 3, Zoom → 4; any other workspace is created on the focused output. Caps Lock is a second `$mod` (`caps:super`), so `Caps+N` switches workspaces one-handed. The workspace segment shows a dot on workspaces that hold windows (from sway's `representation`). `core/SwayState` runs one `swaymsg -m -r -t subscribe '["window","mode","input"]'` and fans out binding mode, xkb layout and window changes (workspace occupancy refresh on new/close/move/floating only, fullscreen probe) - Quickshell's I3 module only forwards workspace/output events.

Notifications: popups stack top-right on the output that was focused when the first one arrived and stay there until the last is gone (4 visible, the rest wait hidden and start a full countdown when they surface; critical 10 s, others `min(expire, 10 s)`, default 5 s), history of 50 in `notifications.json`, `dnd` toggle. Summary and app name render as plain text; the body is Qt StyledText re-serialised by `notifications/Body.js`: only `b i u s em strong del p br` and `<a href="http(s)://...">` pass as tags, every other `<` becomes `&lt;` (Qt's parser aborts a malformed tag early and resumes mid-text, so a strip that mirrors its grammar can be fed a nested `<img>`; escaping everything unknown cannot), Chromium's page-origin prefix is dropped, links open only for `http(s)`, and every `Label` is `PlainText`, so no sender can make the shell fetch a URL. A `replaces_id` update rewrites the live object without a second `onNotification`, so the card listens for summary/body/image changes, resets its countdown and re-snapshots the history row (once the toast has expired the id is gone from the server, so a later `-r` makes a new toast). The popups live in a `ListModel`, so a toast coming or going leaves the other countdowns alone. The countdown pauses while hovered and resumes with what was left; a pointer parked over the stack holds every toast. sway 1.12 sends no `wl_pointer.enter` to a layer surface mapped under a stationary pointer, so `Stack.qml` maps a 1x1 transparent nudge layer on the first frame after a card appears and unmaps it 100 ms later: each map makes sway rebase the cursor against the drawn toast, which then reads as hovered. Left-click runs the default action (else the first), other buttons dismiss; the `qs-glyph` hint replaces the bell when there is no icon.

Lock and idle: `lock/Locker.qml` holds the `ext-session-lock` (`WlSessionLock`) and two `PamContext`s that run as the user: `qs-lock-password` (`pam_unix`; faillock tallies every wrong password, three in a row close the password path for 10 min while the YubiKey path keeps working; PAM's own notice shows in the status line. The tally file `/run/faillock/$USER` sits in a root-only directory the user-run stack cannot create in, so `lock_pam` installs a tmpfiles rule that creates it at boot, otherwise nothing would count until a `sudo` or polkit auth made the file) and `qs-lock-u2f` (`pam_u2f`, touch only, no PIN; the mappings file is group-readable for that). Both PAM files come from `post-install.sh` step `lock_pam`; without the password one `lock()` falls back to a plain `swaylock` child, and `lock status` reports `fallback` for it and `foreign` for a swaylock the shell did not start (both count as locked for the focus gating below). Engaging: `qs-lock` (sway `$mod+Escape`, also `--locked`), the launcher's `Lock` row, the idle ladder, `swayidle lock 'qs-lock'` on logind's Lock signal (lid closed with an external display attached, `HandleLidSwitchDocked=lock`; `loginctl lock-session`), or `swayidle before-sleep 'qs-lock --wait'` (polls `lock status` for `"secure":true` for 3 s, then starts swaylock and gives it the last second of a 4 s budget under logind's 5 s delay). The flag `$XDG_RUNTIME_DIR/qs/locked` is written before the lock is requested and emptied after unlock, so a shell crash, `qs-session restart` or a config reload re-locks on startup (sway keeps the session locked with a red screen in between; `$mod+Escape` re-locks by hand; `FileView` preloads asynchronously even with `blockLoading`, so the check reads `text()`, never `loaded`, before a job was awaited). State lives in `core/Lock` (`locked` = our request, `secure` = compositor confirmed; never bind on `WlSessionLock.locked`, quickshell never emits its change on unlock). While locked, the launcher, popups and polkit prompt drop keyboard focus and stay closed (sway 1.12 lets exclusive layer surfaces take focus from the lock surface; fixed in sway master). The lock screen: blurred wallpaper, clock, one password field mirrored across outputs (`Esc`/`Ctrl+U` clear), `Enter` submits; with a FIDO token present (`udevadm` `ID_FIDO_TOKEN`, watched while locked) `pam_u2f` runs concurrently and a touch unlocks; a failed attempt (token busy, not readable yet, not enrolled) re-arms after a pause that doubles from 750 ms to 5 s and never stops, the hint reads `YubiKey busy, retrying` meanwhile and `YubiKey not accepted, still retrying` after six instant failures. A pending touch is never aborted: a SIGKILLed `pam_u2f` leaves the token busy with that assertion until its own ~29 s timeout, so a password unlock leaves the child waiting (a lock within that window reuses it) and the child's result is ignored once unlocked. The child's run time is wall clock, so a sleep in between shows up in the log as a run of many hours. The field stays editable during the 2 s rejection delay (`Enter` is ignored until the check ends), and a badge names the xkb layout when it is not the first one. `lockBlank` (10 s, `0` disables) idle seconds while locked power the outputs off and clear the field; the key press that wakes them is swallowed (100 ms, plus that key's auto-repeats while it stays held), and sway's `input added` burst after a VT switch back relights outputs the stored `power off` would keep dark. `qs log` carries `lock:` lines (engaged, u2f attempt/result, password rejected, unlocked by); `lock status` adds `u2fActive`, `u2fAttempts`, `u2fFast`. Idle ladder (`lock/Idle.qml`, `IdleMonitor`s on `ext-idle-notify`, compositor-timed so suspend cannot skew them): `idleScreensaver` 900 s → `qs-screensaver start` (`cmatrix` in a fullscreen kitty per output, `inhibit_idle none`), `idleLock` 1800 s → lock (which also stops the screensaver), `idleSuspend` 3600 s → `systemctl suspend-then-hibernate`; `0` disables a rung. The `awake` toggle is an `IdleInhibitor` on the wallpaper layer (always mapped; a hidden bar would not count) - `systemd-inhibit --what=idle` never reached swayidle. No `unlock` IPC exists on purpose; `lock status` never includes typed text. `qs-session` runs quickshell under its own supervisor (`QS_DISABLE_CRASH_HANDLER=1`, relaunch unless three deaths within 60 s; `$XDG_RUNTIME_DIR/qs/supervise.pid` names its process group so `stop`/`restart` take supervisor, shell and child processes down together; before relaunching it kills the dead instance's leftover children, since a PAM fork or `wl-paste --watch` still holding the old D-Bus sockets stops the new shell from registering the notification server and the polkit agent, which quickshell never retries).

Polkit: `polkit/Agent.qml` registers a `PolkitAgent` at `/org/qs/PolkitAgent` and shows one card on the focused output (scrim, exclusive keyboard focus, hidden while locked). The message loses polkit's preamble (`Authentication is required to run \`x' as the super user` → `Run x as the super user`), the identity line names the user. PAM runs its modules one after another, so the password field only exists while PAM asks for text; the rest of the time the same box shows a pulsing status with PAM's own words (`Please touch the FIDO authenticator.` while `pam_u2f` runs first, about 29 s until the token gives up and the password prompt follows; `Checking` after a submit). When the field is shown it has focus and a click lands in it; while it is hidden a `FocusScope` around the card holds the keyboard, so `Esc` cancels at any point (footer says `Esc cancel` or `Esc cancel · Enter submit`). A touch does authenticate `pkexec`: the `pam-u2f` package relaxes the helper's sandbox (`polkit-agent-helper@.service.d/pam-u2f.conf`, `DeviceAllow=char-hidraw`). Cancelling is not free, though: polkit only closes the helper's socket, PAM runs on, `pam_unix` fails its conversation ~29 s later and faillock counts a strike, the same as a wrong password (three within 15 min close the password path for 10 min; `faillock --user $USER` shows them). PAM info lines show below the field only when they arrived with the prompt or during it (faillock's lockout notice); the touch cue from the phase before is not repeated there, since quickshell never clears `supplementaryMessage`. A wrong password shakes the card, borders it red and says `Authentication failed` while polkit starts the next attempt from the touch phase. `qs-shell polkit status` → `{registered, active, responseRequired}`.

Reboot required: `core/System.qml` watches `/run/reboot-required` (written by the pacman hook `zz-reboot-required.hook` for kernels/systemd/glibc/mesa/firmware/…, installed by `post-install.sh` step `pacman_hooks`) and checks `/usr/lib/modules/$(uname -r)` once at startup (gone after a kernel upgrade). No polling, no notification: shows ↻ in Indicators and a yellow dot on `Packages`/`Update`/`Reboot` rows until reboot (`/run` is tmpfs).

Theme: Catppuccin Mocha, hardcoded in `core/Theme.qml` (named `Theme`, not `Color` - Qt 6.12 ships a `QtQuick/Color` singleton that shadows a singleton of ours by that name). GTK 3/4 share one `gtk/` dir (→ `~/.config/gtk-3.0` and `gtk-4.0`): `gtk.css` sets the libadwaita named colours, `settings.ini` is the fallback; `adw-gtk3-dark` + dark `color-scheme` + fonts go through `gsettings` in `post-install.sh` step `theme`, because GTK3 on Wayland reads `org.gnome.desktop.interface` and ignores `settings.ini` for those keys. Qt apps (incl. `pinentry-qt`) use `qt6ct/` (Fusion, `colors/catppuccin-mocha.conf`, Adwaita Sans) via `QT_QPA_PLATFORMTHEME=qt6ct` from `zsh/.zprofile`; `qs-session` imports it into the systemd user environment so gpg-agent's pinentry gets it too. Quickshell is unaffected: text takes font and colour from `core/Style`/`core/Theme` (through `ui/Label`/`ui/Glyph` almost everywhere) and `shell.qml` starts with `//@ pragma NativeTextRendering`, so every `Text` renders native-hinted.

Launcher: command menu - breadcrumb, frecency (`~/.local/state/qs/launcher-usage.json`, keys namespaced per section), wallpaper thumbnail grid, `=expr` calculator. Root search also covers System, Packages, Capture, Toggle, Setup and every Keybindings section (rows show a `↳ Section` crumb); name matches rank above keyword matches, then frecency. Apps lists only explicitly installed packages' desktop entries (`bin/qs-apps`), minus `quickshell/apps-hide` (`C--` on a row blacklists it after confirmation). System → `Roll back last update` runs `snap-restore last` in a `qs-task` window (sudo touch, then its own y/N). Packages → `qs-pkg` in a `qs-task` window: fzf pickers for pacman (`alt-b` PKGBUILD), AUR (`yay`, `yay-git` when the AUR is unreachable), remove (`pacman -Rns`), update (`yay -Syu`). When the rows do not fit the card (520 px) the list ends mid-row - a row clipped at 55 % is the cue that more sits below the fold - and moving the cursor keeps the neighbouring row peeking past it on both sides; the wallpaper grid folds the same way by rows of thumbnails. The cursor follows the pointer only when the pointer actually moves (more than 1 px), never when the list scrolls under a resting pointer or the card opens beneath it. Two key modes, shown in the header:

| Mode | Keys |
| --- | --- |
| INSERT (default) | type to filter · `C-j`/`C-k` move · `C-d`/`C-u` half-page · `C-o` clear search · `C-l` descend · `C-h` back (closes at root) · `C-y` copy row · `C-w` delete word (Backspace and `C-Backspace` only edit the text) · `C-r` refresh app list · `Left`/`Right` move the caret · `Esc` normal mode |
| NORMAL | `j`/`k` · `gg`/`G` · `h` back / clear search (restores the row you left) · `l` descend · `Enter`/`Space` activate · `y` copy · `p` copy clipboard row + close · `d`/`x` delete (clipboard) · `1-9` jump · `r` refresh app list · `C--` blacklist app · `i` insert · `Esc`/`q` close |
| Popups (`$mod+o` …) | no on-screen legend; `Esc`/`q` close everywhere, arrows/Home/End/PgUp/PgDn too |
| Audio (`$mod+o a`) | `j`/`k` row (out mute → mic mute → out volume → sinks → in volume → sources → apps; device rows only with more than one device) · `h`/`l` ±5 % · `m` mute row · `Enter` mute/pick. App rows drive every stream of that app. The INPUT slider carries a green level bar while the card is open: the linear sample peak (quickshell reports a cube-root curve that would park a quiet room near half scale, so it is cubed back), silence a few percent, speech mid-bar, clipping full. |
| Clock (`$mod+o c`) | `h`/`l` month · `j`/`k` year · `t` today. Weeks start Monday, ISO week numbers |
| Battery (`$mod+o b`) | `j`/`k` power profile · `c` charge limit on/off (UPower thresholds 75→80 %, `bin/qs-battery`; `post-install.sh` step `battery_limit` turns it on) · `p` toggle %. Auto power-saver on battery (`powerSaverOnBattery`) |
| Network (`$mod+o n`) | `j`/`k` · `Enter` connect/disconnect (inline PSK, WPA-EAP identity) · `w` Wi-Fi on/off · `r` rescan · captive portal row when NM reports Portal |
| Weather (`$mod+o w`) | current conditions, sunrise/sunset, night-light mode · `e` change city (open-meteo geocoding) · `d` back to IP location · `u` °C/°F · `r` refresh |
| Tray menu (right-click icon) | `j`/`k` row · `l`/`Enter` activate or enter submenu · `h` back (closes at top level). Checked entries show `✓`. |
| Media (`$mod+o m`, `$mod+Shift+p`) | cover · title · artist · album · `p` play-pause · `h`/`l` (or `[`/`]`) prev/next · `j`/`k` volume. Volume is the player's PipeWire stream (matched by process binary / app name / node name against the MPRIS identity and desktop entry, both reduced to alphanumerics; up to 150 % like the audio popup), falling back to MPRIS (0-100 %). Global: `$mod+p`, `$mod+[`/`]` go through `qs-shell media toggle/next/previous`, so keys, bar and popup always drive the same player; the OSD toast waits for the MPRIS state to actually change (120 ms polls, 1.2 s cap) instead of guessing a delay. Player choice: Feishin, else a playing player with a live PipeWire stream, else any playing player, else one with track metadata, else the first; `playerctld`'s proxy is ignored. |

| `bin/`                 | Purpose                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `qs-shell [-q] T FN`   | `qs ipc call` wrapper; exits 1 on unknown target/function/no instance (`qs ipc` says so with exit 0), 3 s timeout, finds the display from `$XDG_RUNTIME_DIR/wayland-*` when unset |
| `qs-quit`              | SIGTERM the focused window's process (`$mod+Ctrl+q`; apps that hide to the tray on `kill` actually exit) |
| `qs-session`           | `start` (sway `exec`), `restart` (`$mod+Shift+r`), `stop`, `supervise` (internal relaunch loop) |
| `qs-toggle NAME`       | `awake` `nightlight` `dnd` `bar-hidden` - flag files; nightlight also runs `wlsunset` as a transient unit |
| `qs-lock [--wait]`     | lock via IPC (`swaylock` fallback); `--wait` blocks until the compositor confirms, 4 s max |
| `qs-screensaver MODE`  | `start` `stop` - fullscreen `cmatrix` kitty per output (`app_id` `qs-screensaver`); no-op without `cmatrix` |
| `qs-capture MODE`      | `region` `window` `screen` `region-clip` `color`                          |
| `qs-wallpaper`         | `set PATH` `random` `current` `list`                                      |
| `qs-notify`            | `notify-send` via `busctl`; `-r ID` replace, `-p` print id, `-g GLYPH` (hint `qs-glyph`, shown without icon) |
| `qs-weather`           | `refresh` `set CITY` `clear` `status` - open-meteo → `weather.json`        |
| `qs-battery`           | `status` `limit [on\|off]` - UPower charge thresholds (JSON)              |
| `qs-network-status`    | internal, JSON for the network popup (ip/gateway/ping/traffic)             |
| `qs-clipboard-capture` | internal, `wl-paste --watch` target                                       |
| `qs-apps`              | `list` `hide ID` - explicitly installed desktop ids minus `apps-hide`; pacman hook touches `/run/qs-apps-changed` to re-list |
| `qs-task CMD…`         | run CMD in a floating 75 % kitty window, `Done!`/`Failed` + Enter to close |
| `qs-pkg MODE`          | `install` `aur` `remove` `update` `pkgbuild PKG` - fzf package pickers    |
| `qs-wifi-prefer SSID`  | autoconnect-priority 10 for SSID's profile, 0 for other Wi-Fi profiles    |
| `yay-git PKG…`         | build AUR packages from git (AUR, GitHub mirror fallback), AUR deps recursive |
| `snap-restore`         | `list` `last` `N` `undo` `rebuild`, `--device DEV` from the ISO - root rollback to a snapper snapshot, UKIs rebuilt inside it (Recovery below) |

State: `~/.local/state/qs/` (`toggles/`, `settings.json`, `notifications.json`, `clipboard.json`, `clipboard-images/`, `weather.json`, `weather-location.json`, `launcher-usage.json`, `background`). Clipboard history skips `x-kde-passwordManagerHint` sources (1Password) - the file is still plaintext, rely on LUKS.

IPC targets (`qs-shell T FN`): `launcher` (toggle/open) · `popups` (toggle/open) · `lock` (lock → `ok`/`already`/`fallback`, status JSON) · `media` (toggle/next/previous) · `notifications` (dismissLatest/actionLatest; sway `$mod+Shift+d` / `$mod+Shift+a`) · `clipboard` (refresh) · `osd` (brightness) · `background` (refresh) · `toggles` (refresh) · `polkit` (status JSON, a diagnostic: registered/active/responseRequired) · `shell` (ping/resume).

Lint: `quickshell/lint.sh` (qmllint, must be clean).

---

## Recovery

- Boots, but broken since an update: `snap-restore` lists the snapshots (it re-runs itself under `sudo`); `snap-restore last` (also the launcher's System → Roll back last update) swaps `@` for the snap-pac `pre` snapshot of the last pacman run, rebuilds both UKIs inside it (kernel on the ESP = modules in the root) and offers the reboot. `snap-restore N` for any other snapshot. The replaced root stays as `@_replaced`, with its disk space, until the next restore deletes it; `snap-restore undo` swaps it back (one level, not a history). Not `snapper rollback` (openSUSE layout).
- The kernel does not boot: hold Space at power-on → systemd-boot menu → `arch-linux-lts.efi`, then `snap-restore last`. Covers a kernel regression only: both UKIs share the initramfs config and rebuild in the same transaction.
- Nothing boots: live ISO → `cryptsetup open /dev/<luks-partition> cryptroot` → `mount -o subvol=@home /dev/mapper/cryptroot /mnt` → `/mnt/<user>/projects/dotfiles/bin/snap-restore --device /dev/mapper/cryptroot list`, then `last` or `N` (same script; `arch-chroot` is on the ISO). `rebuild` instead only rebuilds the UKIs from the current `@` (broken initramfs, root fine; also the way out when a restore's own rebuild failed).
- LUKS header damaged (no keyslot opens, `cryptsetup luksDump` fails): live ISO, `cryptsetup luksHeaderRestore /dev/<luks-partition> --header-backup-file <usb>/luks-header-YYYYMMDD.img` from the step 5 USB; keyslots revert to that date.
- Neither key unlocks: boot without key, passphrase (keyslot 0) after 30 s. FIDO2 PIN blocked or applet wiped → [YUBIKEY.md](./YUBIKEY.md#recovery).
- Red screen, no lock prompt (shell died while locked): `$mod+Escape` re-locks (bound `--locked`), or from another VT `WAYLAND_DISPLAY=wayland-1 SWAYSOCK=$(ls /run/user/1000/sway-ipc.*) qs-session restart`, which re-locks from the flag. Lock screen itself broken: from the VT `qs-session stop`, then `WAYLAND_DISPLAY=wayland-1 swaylock` (replaces the abandoned lock), unlock on the sway VT, fix, `qs-session start` (drops the stale flag; `restart` would re-lock).
- Lock prompt refuses a correct password: usually faillock (three wrong tries within 15 min close the password path for 10 min; the status line shows PAM's notice): wait, unlock with the YubiKey, or `faillock --user $USER --reset` as root. A broken `/etc/pam.d/qs-lock-password` → `post-install.sh --redo lock_pam` (when the file is missing `qs-lock` falls back to `swaylock` by itself).
