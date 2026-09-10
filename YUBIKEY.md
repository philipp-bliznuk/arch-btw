# YubiKey Provisioning

Two YubiKey 5-series, wiped and rebuilt so **either works everywhere**. Done on macOS; `ykman`/`gpg` commands identical on Linux. Prerequisite to [README.md](./README.md).

- FIDO2 is non-cloneable → register **both** keys on **every** account.
- GPG/SSH is cloned → **same** subkeys on both cards → zero reconfiguration on swap. Can't revoke one without the other.
- OATH-TOTP is per-key → enroll the same seed on each (~32 slots per key).

Order: Part 0 extract → Part A key #1 → Part B key #2 → Part C register. No account touched until both keys are built.

## Prerequisites

```zsh
brew install gnupg ykman pinentry-mac   # ykman GUI is EOL; CLI only
ykman list && ykman info
```

Yubico Authenticator (App Store) — only tool for OATH; supplies the clock. macOS has PC/SC built in — no `pcscd`.

Five secrets, all into 1Password:

| #   | Secret                 | Default             | Notes                                                            |
| --- | ---------------------- | ------------------- | ---------------------------------------------------------------- |
| 1   | GPG certify passphrase | —                   | Protects offline primary. Only for certifying new subkeys.       |
| 2   | OpenPGP User PIN       | `123456`            | Sign / decrypt / SSH.                                            |
| 3   | OpenPGP Admin PIN      | `12345678`          | `keytocard`, touch policy. **Exhausted = applet wiped, no PUK.** |
| 4   | FIDO2 PIN              | none                | WebAuthn + LUKS/login. 8 tries → `ykman fido reset`.             |
| 5   | PIV                    | `123456`/`12345678` | Left at reset.                                                   |

Applets are independent — resetting one doesn't touch the others.

---

# Part 0 — Extract

For every account: remove both keys' FIDO2/passkey registrations, delete key-held TOTP, set a **temporary** TOTP in a dedicated authenticator app (Aegis / 2FAS / Ente — **never the password manager**; it's also the permanent home for TOTP-only accounts).

Permanent plan per account (executed in Part C):

1. FIDO2 on both keys — every account that supports security keys, **especially the password manager's own login**.
2. Authenticator app — TOTP-only accounts.
3. Printed recovery codes offline — never screenshot / cloud / vault.

---

# Part A — Key #1

Insert **only** key #1.

## A1 — Reset

```zsh
ykman info
ykman openpgp reset    # wipes GPG keys, PINs back to 123456/12345678
ykman fido reset       # wipes all WebAuthn creds + FIDO2 PIN
ykman oath reset       # wipes TOTP seeds
ykman piv reset
```

## A2 — Interfaces

```zsh
ykman config usb --disable otp    # legacy OTP transport unused
ykman config nfc --disable otp
ykman config set-lock-code        # into 1Password
```

## A3 — FIDO2 PIN

```zsh
ykman fido access change-pin      # 8+ chars; set-min-length needs fw 5.7+, firmware is not upgradable
```

## A4 — Harden OpenPGP

```zsh
gpg --card-edit
# gpg/card> admin
# gpg/card> kdf-setup             # FIRST — resets both PINs to factory
# gpg/card> quit
ykman openpgp access set-retries 8 8 8       # user / reset-code / admin; reset code stays unset
ykman openpgp access change-admin-pin        # default 12345678
ykman openpgp access change-pin              # default 123456
```

## A5 — Generate identity, load card

```zsh
gpg --expert --full-generate-key
# (11) ECC set own capabilities → S toggles Sign OFF → only Certify → Q
# (1) Curve 25519 → expiry 0 → name/email → certify passphrase (secret #1)
gpg --list-secret-keys --keyid-format long   # sec line must say usage: C, not SC — else delete and redo with (11)
```

```zsh
gpg --expert --edit-key <key-id>
# addkey → (10) ECC sign only    → Curve 25519 → 0
# addkey → (12) ECC encrypt only → Curve 25519 → 0
# addkey → (11) ECC set own → only Authenticate → Curve 25519 → 0
# save
gpg --list-secret-keys --keyid-format long   # sec C + ssb S/E/A
```

Backup **before** `keytocard` (it moves secrets off disk, leaves stubs):

```zsh
gpg --armor --export-secret-keys    <key-id> > primary-and-subkeys.asc
gpg --armor --export-secret-subkeys <key-id> > subkeys-only.asc          # clone source for key #2
gpg --armor --export                <key-id> > public.asc
gpg --gen-revoke                    <key-id> > revoke.asc
```

All four encrypted + offline (USB), not in the vault.

```zsh
gpg --expert --edit-key <key-id>
# key 1 → keytocard → 1 (Signature)      → key 1
# key 2 → keytocard → 2 (Encryption)     → key 2
# key 3 → keytocard → 3 (Authentication) → key 3
# save
gpg --list-secret-keys                       # ssb> = on card
gpg --card-edit                              # admin → name (cardholder, cosmetic)
```

```zsh
ykman openpgp keys set-touch sig cached      # cached = touch, then 15 s grace; on = every time; fixed = immutable
ykman openpgp keys set-touch dec cached
ykman openpgp keys set-touch aut cached
```

## A6 — SSH via gpg-agent (macOS)

`~/.gnupg/gpg-agent.conf`:

```conf
pinentry-program /opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid   # or /opt/homebrew/bin/pinentry-mac
enable-ssh-support
default-cache-ttl 60      # idle timeout; raise in dotfiles (86400)
max-cache-ttl 120         # absolute; raise in dotfiles (604800)
```

- `pinentry-touchid` (`brew install jorgelbg/tap/pinentry-touchid`) only gates **on-disk** key passphrases; card enforces its own PIN + touch. Needs `pinentry-mac` as fallback. Single global setting.
- PIN cache lives in gpg-agent RAM, cleared on reboot / logout / `gpgconf --kill gpg-agent` / unplug.

`~/.zshrc`:

```zsh
export GPG_TTY=$(tty)
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent
```

```zsh
gpgconf --kill gpg-agent
ssh-add -L                                       # one ssh-ed25519 line = Auth subkey
ssh-add -L | grep 'cardno:' > ~/.ssh/id_ed25519_ic_yubikey.pub
```

- One SSH key = one GitHub account. Card key covers a single account; other accounts get on-disk keys (`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<id>`).
- `IdentitiesOnly yes` requires `IdentityFile` even for the agent key — without it SSH ignores the agent → `Permission denied (publickey)`.

`~/.ssh/config`:

```
Host ic
    HostName github.com
    User git
    IdentityAgent ~/.gnupg/S.gpg-agent.ssh
    IdentityFile ~/.ssh/id_ed25519_ic_yubikey.pub
    IdentitiesOnly yes

Host pb
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_pb
    IdentitiesOnly yes
```

Remotes: `git@ic:org/repo.git`.

## A7 — Git signing

```zsh
git config --global user.signingkey <sign-subkey-id>!   # ! pins the subkey; ssb [S] line
git config --global commit.gpgsign true
git config --global gpg.format openpgp
gpg --armor --export <key-id>                           # GitHub → Settings → GPG keys (not SSH keys); same key on every account
```

- Verified badge needs `user.email` matching a key UID.
- Signing prompts **User PIN + touch**. User PIN exhausted → `gpg --card-edit` → `admin` → `passwd` (Admin PIN). Admin PIN exhausted → applet wiped.
- Per-account identity via `~/.config/git/config`:

```
[includeIf "hasconfig:remote.*.url:git@ic:**/**"]     # **/** — single ** doesn't match scp-style remotes; git ≥ 2.36
    path = ~/.config/git/ic
```

## A8 — Verify

```zsh
ykman info
ykman openpgp info               # KDF on, 8/8/8, touch cached
gpg --card-status                # three subkeys
ssh-add -L
echo test | gpg --clearsign      # touch + User PIN
```

---

# Part B — Key #2

Remove key #1. Insert **only** key #2.

## B1 — Reset + interfaces + FIDO2 PIN

```zsh
ykman info
ykman openpgp reset && ykman fido reset && ykman oath reset && ykman piv reset
ykman config usb --disable otp && ykman config nfc --disable otp
ykman config set-lock-code
ykman fido access change-pin
```

## B2 — Harden OpenPGP

```zsh
gpg --card-edit                              # admin → kdf-setup → quit  (FIRST)
ykman openpgp access set-retries 8 8 8
ykman openpgp access change-admin-pin        # SAME as key #1
ykman openpgp access change-pin              # SAME as key #1
```

## B3 — Clone subkeys

```zsh
gpg --delete-secret-keys <key-id>            # drops on-disk stubs only; key #1 untouched
gpg --import subkeys-only.asc
gpg --list-secret-keys --keyid-format long   # plain ssb, not ssb# / ssb>
gpg --expert --edit-key <key-id>
# key 1 → keytocard → 1 ; key 2 → keytocard → 2 ; key 3 → keytocard → 3 ; save
ykman openpgp keys set-touch sig cached
ykman openpgp keys set-touch dec cached
ykman openpgp keys set-touch aut cached
```

## B4 — Verify + swap test

```zsh
ykman openpgp info
gpg --card-status                # same subkeys, different serial
ssh-add -L                       # identical line to key #1
```

Swap keys, then:

```zsh
gpg-connect-agent "scd serialno" "learn --force" /bye   # re-point stubs at the inserted card; needed on every swap
echo test | gpg --clearsign
```

---

# Part C — Register

- **C1 FIDO2**: every security-key account (GitHub, AWS, Google, Auth0, password manager) — add key #1, then key #2. Name them `yubikey-1` / `yubikey-2`.
- **C2 Card TOTP**: top-value TOTP-only accounts → Yubico Authenticator, same QR/seed on both keys, one sitting. ~32 slots.
- **C3 App TOTP**: everything else → authenticator app. Not the password manager.
- **C4 Recovery codes**: fresh set per account, printed, offline.
- Remove the temporary 2FA from Part 0.

---

Next: [README.md](./README.md) — `install.sh` enrolls both keys for LUKS; `post-install.sh` wires PAM + GPG/SSH.
