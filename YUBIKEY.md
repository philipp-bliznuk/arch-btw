# Provisioning Your YubiKeys

A from-scratch guide to wiping two YubiKey 5-series keys and configuring every
feature that makes sense for a security-conscious workstation: FIDO2/WebAuthn,
OpenPGP (GPG for commit signing + SSH authentication), and OATH-TOTP for
one-time codes.

This is an **optional prerequisite** to the main Arch install guide
([README.md](./README.md)). If you plan to unlock LUKS, log in, sign commits, or
authenticate SSH with a YubiKey, do this first — the install guide assumes your
keys are already provisioned.

Everything here is done on **macOS** (the keys get registered to accounts you
manage in 1Password), but every `ykman`/`gpg` command is identical on Linux.

## Philosophy

Two keys, configured so that **either one works everywhere**. One lives on your
keyring, the other in a drawer as a backup. The catch is that not every
credential type can be cloned:

- **FIDO2 / WebAuthn is non-cloneable by design.** The private key is generated
  on the chip and never leaves it. That is the whole point — a stolen key can't
  be copied. The consequence: each key registers a **distinct** credential with
  every account, so you must add **both** keys to **every** account separately.
- **GPG / SSH is cloneable by choice.** You generate the keys off-device, back
  them up, and load the **same** subkeys onto both YubiKeys. Why identical rather
  than distinct? Because Git names exactly one signing key
  (`user.signingkey`) and each server holds one SSH public key — identical keys
  mean **zero reconfiguration** when you swap from the primary to the backup.
  The tradeoff is that you can't revoke one without revoking the other, which is
  acceptable because the private material can never be extracted from a stolen
  key anyway.
- **OATH-TOTP is per-key.** The seeds can't be read back off the key, so you
  enroll each account on each key (or keep the QR/seed and add it to both).

> **Order matters.** First **extract** both keys from every account and park a
> temporary 2FA (Part 0), so the keys are free to wipe. Then **configure** Key #1
> (Part A) and Key #2 (Part B) fully — no account registration, no time pressure.
> Only once both keys are built do you **register** them to accounts (Part C).
> This keeps you logged in throughout and means you touch each account's 2FA
> settings exactly once.

## Section 0 — Prerequisites

### Tooling

```zsh
brew install gnupg ykman pinentry-mac
```

- `gnupg` — key generation, `keytocard`, the GPG agent that also serves SSH.
- `ykman` — YubiKey Manager CLI. (The old YubiKey Manager **GUI** is
  end-of-life as of Feb 2026 — use the CLI.)
- `pinentry-mac` — native PIN prompt. On Apple Silicon it lands at
  `/opt/homebrew/bin/pinentry-mac`; on Intel, `/usr/local/bin/pinentry-mac`.
- **Yubico Authenticator** (from the Mac App Store or yubico.com) — the only
  tool for managing OATH-TOTP, and it provides the clock the key needs (the key
  has no battery, so the host supplies the time).

macOS has a PC/SC smart-card stack built in; there is nothing like `pcscd` to
install or start.

Confirm a key is seen:

```zsh
ykman list
ykman info
```

### The five secrets

Provisioning creates up to five independent secrets. They protect different
applets and are **not** interchangeable. Store every one in 1Password as you set
it.

| #   | Secret                   | Applet / scope           | Factory default                 | Notes                                                                                 |
| --- | ------------------------ | ------------------------ | ------------------------------- | ------------------------------------------------------------------------------------- |
| 1   | GPG certify passphrase   | Your offline primary key | you choose                      | Protects the master backup, not the card. Needed only to certify new subkeys.         |
| 2   | OpenPGP **User** PIN     | OpenPGP applet           | `123456`                        | Day-to-day: sign, decrypt, SSH-auth.                                                  |
| 3   | OpenPGP **Admin** PIN    | OpenPGP applet           | `12345678`                      | Provisioning: `keytocard`, touch policy. **3 wrong tries = applet wiped, keys gone.** |
| 4   | FIDO2 PIN                | FIDO2 applet             | none until set                  | WebAuthn + (on Linux) LUKS/login. 8 tries, then `ykman fido reset`.                   |
| 5   | PIV PIN / PUK / mgmt key | PIV applet               | `123456` / `12345678` / default | Only if you provision PIV (this guide leaves PIV at reset).                           |

> **The applets are separate stores on one chip.** Resetting or locking one does
> not touch the others. The single most dangerous secret is the **OpenPGP Admin
> PIN**: three wrong entries permanently wipe the OpenPGP applet — there is no
> PUK for it — so write it down before you change it.

---

# Part 0 — Extract and park

Before wiping anything, remove **both** YubiKeys from every account so nothing
depends on them. If you reset a key while an account still lists it as the only
second factor, you lock yourself out. Clearing the keys first also lets you
reset and rebuild them with no time pressure.

For each account: remove the YubiKey FIDO2/passkey registrations and delete any
YubiKey-held TOTP, then set a **temporary** second factor so you stay logged in.
Use a **dedicated authenticator app** (Aegis, 2FAS, or Ente Auth) for the
temporary TOTP — it is also the permanent home for the bulk of your TOTP-only
accounts, so most of this work is not throwaway.

> **Second-factor strategy.** Decide, per account, where each factor will
> _permanently_ live — this shapes what you register in Part C:
>
> 1. **FIDO2 on the YubiKey** for every account that supports security keys
>    (GitHub, AWS, Google, Auth0, your password manager's own login). Strongest
>    factor, phishing-proof, hardware-bound — register **both** keys on each.
> 2. **A dedicated authenticator app** for TOTP-only accounts. Keep it **out of
>    your password manager** — storing an account's TOTP in the same vault as its
>    password collapses two factors into one. This is the crux rule.
> 3. **Offline recovery codes** as the anti-lockout net (printed, in a safe —
>    never a screenshot, never synced to the cloud or the vault). This, plus the
>    second registered key, is what saves you if both YubiKeys are lost.
>
> Each YubiKey's OATH applet holds only ~32 TOTP credentials. Seeds don't clone,
> so an account you want on both keys must be enrolled on each one separately —
> the enrollment effort doubles, the per-key capacity does not. Either way the key
> is **not** where 100+ TOTP accounts live — reserve its slots for a handful of
> top-value ones (Part C, C2). And harden your password manager's **own** login
> with both keys' FIDO2: highest-leverage single move you can make.

Once both keys are removed from every account and a temporary factor is in place,
they're safe to reset. Proceed to Part A.

---

# Part A — Key #1 (configure only)

Insert **only Key #1**. Do not insert Key #2 until Part B. Configure the key
fully here — there is **no account registration in this part**; that happens in
Part C, once both keys are built.

## A1 — Inventory and factory reset

See what's on the key and what firmware it runs:

```zsh
ykman info
```

Reset each applet you'll use. Each reset is independent and irreversible:

```zsh
ykman openpgp reset
ykman fido reset
ykman oath reset
ykman piv reset
```

> **Reset blast radius.** `ykman fido reset` erases every WebAuthn/passkey
> credential and the FIDO2 PIN — you will re-register this key with every
> account. `ykman openpgp reset` erases the GPG keys and resets the User/Admin
> PINs to `123456`/`12345678`. `ykman oath reset` erases all TOTP seeds. None of
> these touch the other applets.

## A2 — Interface hygiene (optional)

Disabling transports you won't use shrinks the attack surface. This guide uses
FIDO2, OpenPGP, and OATH — the legacy OTP transport (Yubico OTP / static
password / challenge-response) is unused:

```zsh
# Optional: disable the legacy OTP application on both USB and NFC.
ykman config usb --disable otp
ykman config nfc --disable otp
```

You can also require a lock code to change the config later:

```zsh
# Optional: prevents applet enable/disable without this code. Store it in 1Password.
ykman config set-lock-code
```

Skip both if you're unsure — they're conveniences, not security-critical.

## A3 — FIDO2 PIN

Set a FIDO2 PIN. Choose **8+ characters** — FIDO2 allows 4–63, and a longer PIN
is your own policy since it can't be enforced on the key (see note):

```zsh
ykman fido access change-pin
```

> **No minimum-length enforcement on pre-5.7 firmware.** `ykman fido access
set-min-length` needs the CTAP2.1 `setMinPINLength` feature, which arrived in
> YubiKey firmware **5.7**. Older keys (check `ykman info`) simply can't enforce
> a floor, so just pick a long PIN yourself. Firmware is fixed at manufacture and
> can't be flashed, so there's no upgrade path — this is a hardware limit, not a
> setting.

## A4 — Harden the OpenPGP applet

Do this **before** loading keys, so the keys are protected by your PINs and
policy from the moment they land.

First enable KDF (hashed-PIN storage). `ykman` has no `set-kdf` command — KDF is
managed through GnuPG:

```zsh
gpg --card-edit
```

At the `gpg/card>` prompt:

```
admin
kdf-setup
quit
```

> **KDF first, and it resets the PINs.** `kdf-setup` stores the User/Admin PINs
> hashed on-card instead of in the clear — but it resets both PINs back to their
> factory defaults (User `123456`, Admin `12345678`). So run it **before** the
> `ykman` PIN changes below, not after, or you'll set PINs and immediately wipe
> them.

Now raise the retry counters and change both PINs off their defaults:

```zsh
# Retry counters: user / reset-code / admin.
ykman openpgp access set-retries 8 8 8

# Change both PINs off their factory defaults. Store both in 1Password.
ykman openpgp access change-admin-pin      # default 12345678
ykman openpgp access change-pin            # default 123456
```

> Retry counters: the middle value is the reset-code counter (leave the reset
> code unset — the Admin PIN is your recovery path). A fully exhausted Admin
> counter means `ykman openpgp reset` and regenerating from your backup, so
> 8/8/8 gives comfortable margin.

Set cardholder identity (cosmetic but tidy) while you're here — done via GPG in
A5's `--card-edit`.

## A5 — Generate the GPG identity and load it

This is the identity you will **clone** to Key #2, so generate it on the host,
back it up, then move copies onto the card.

### Generate a certify-only primary + three subkeys

```zsh
gpg --expert --full-generate-key
```

- Choose **(11) ECC (set your own capabilities)**. GPG opens a toggle menu; the
  primary starts with **Sign + Certify** enabled. Press `S` to **toggle Sign
  off**, leaving **only Certify (C)**. (Leave Authenticate off too.) Then `Q`.
- Curve: **(1) Curve 25519**.
- Expiry: **0** (does not expire — your revocation certificate is the mitigation).
- Enter your name and email; set a strong **certify passphrase** (secret #1).

> **Watch the primary's usage flag.** The default `--full-generate-key` flow
> (and picking a ready-made ECC option) produces a primary with `usage: SC`
> (Sign **and** Certify). You want `usage: C` — certify-only. If `gpg
--list-secret-keys` shows `SC` on the `sec` line, you took the wrong option;
> delete it (`gpg --delete-secret-keys <key-id>` then `gpg --delete-keys
<key-id>`) and redo with option **(11)**, toggling Sign off. A certify-only
> primary is what lets the primary stay offline while the dedicated Sign
> **subkey** does all day-to-day signing.

Add the three subkeys:

```zsh
gpg --expert --edit-key <key-id>
```

At the `gpg>` prompt, three times:

- `addkey` → **(10) ECC sign only** → Curve 25519 → expiry **0**.
- `addkey` → **(12) ECC encrypt only** → Curve 25519 → expiry **0**.
- `addkey` → **(11) ECC set your own capabilities** → toggle to leave **only
  Authenticate** → Curve 25519 → expiry **0**.
- `save`.

Confirm the shape (`sec` = C, three `ssb` = S/E/A):

```zsh
gpg --list-secret-keys --keyid-format long
```

### Back up before anything touches the card

`keytocard` **moves** the subkey secret onto the card and leaves only a stub on
disk. Back up first, or you can never clone Key #2:

```zsh
gpg --armor --export-secret-keys    <key-id> > primary-and-subkeys.asc
gpg --armor --export-secret-subkeys <key-id> > subkeys-only.asc
gpg --armor --export                <key-id> > public.asc
gpg --gen-revoke                     <key-id> > revoke.asc
```

- `subkeys-only.asc` is what you'll import when cloning Key #2 — keep it safe.
- Store all four **encrypted and offline** (e.g. an encrypted USB stick, not in
  1Password's normal vault). Keep the primary key material offline after this.

### Move the subkeys onto Key #1

```zsh
gpg --expert --edit-key <key-id>
```

At `gpg>`:

- `key 1` (select the Sign subkey) → `keytocard` → slot **1 (Signature)** →
  `key 1` again to deselect.
- `key 2` → `keytocard` → slot **2 (Encryption)** → `key 2` to deselect.
- `key 3` → `keytocard` → slot **3 (Authentication)** → `key 3` to deselect.
- `save`.

`gpg --list-secret-keys` now shows the subkeys as `ssb>` (on-card stubs). Set
cardholder name/URL here too if you like: `gpg --card-edit` → `admin` → `name`.

### Require a touch per operation

```zsh
ykman openpgp keys set-touch sig cached
ykman openpgp keys set-touch dec cached
ykman openpgp keys set-touch aut cached
```

> `cached` means touch once, then a 15-second grace window — a good balance for
> a signing/SSH workflow. Use `on` for touch-every-time, or `fixed` to make the
> policy itself unchangeable (can't be relaxed without wiping the applet).

## A6 — SSH through the GPG agent

Point the GPG agent at a pinentry, enable SSH support, and route the SSH
socket to the agent.

`~/.gnupg/gpg-agent.conf`:

```conf
pinentry-program /opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid
enable-ssh-support
default-cache-ttl 60
max-cache-ttl 120
```

> **On `pinentry-touchid`.** `brew install jorgelbg/tap/pinentry-touchid` gates an
> **on-disk** key's passphrase behind Touch ID and caches it in the macOS Keychain
> (first use still prompts for the passphrase with a "Save in Keychain" box; after
> that it's Touch ID). It needs `pinentry-mac` present as a fallback. It does **not**
> intercept the YubiKey — the card enforces its own OpenPGP User PIN + physical
> touch, which Touch ID cannot replace. `pinentry-program` is a single global
> setting; you cannot route it per key. If you don't use Touch ID, point it at
> `/opt/homebrew/bin/pinentry-mac` instead.
>
> **On the cache TTLs.** `60`/`120` are deliberately conservative. The User PIN is
> cached by **gpg-agent (RAM), not the Keychain** — `default-cache-ttl` is the idle
> timeout (reset on each use), `max-cache-ttl` the absolute ceiling from first
> entry. Raise both in your personal dotfiles for fewer PIN prompts (e.g. `86400`
> and `604800` = re-enter roughly once a day / once a week). The cache is wiped on
> reboot, logout, `gpgconf --kill gpg-agent`, or unplugging the key. Longer windows
> trade convenience for the risk that someone at your unlocked Mac can sign — though
> they still need the physical key inserted and a fresh touch.

`~/.zshrc` (or `~/.zprofile`):

```zsh
export GPG_TTY=$(tty)
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent
```

Reload and confirm the Authentication subkey is offered:

```zsh
gpgconf --kill gpg-agent
ssh-add -L        # prints one ssh-ed25519 line = your Auth subkey
```

Add that single public key to **one** GitHub account (and to any servers'
`authorized_keys`). Both YubiKeys present the **same** SSH key, so you add it
once per destination.

> **One SSH key per GitHub account.** GitHub rejects an SSH key that is already
> attached to another account ("key is already in use") — a public key
> identifies exactly one account by design. Since both your keys clone the _same_
> auth subkey, YubiKey-backed SSH covers a **single** account. Each additional
> account simply needs its **own** SSH key: generate an ordinary on-disk key
> (`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_personal`) and select it per-remote
> with `~/.ssh/config` host aliases. HTTPS (a Personal Access Token or the `gh`
> CLI) stays as a low-effort fallback. Commit **signing** works on all accounts
> via GPG below regardless. Tradeoff: on-disk keys are ordinary files — not
> hardware-protected like the YubiKey auth key — so it's a security-vs-convenience
> call per account.

```
# YubiKey-backed account (auth via gpg-agent)
Host github-work
    HostName github.com
    IdentityAgent ~/.gnupg/S.gpg-agent.ssh
    IdentityFile ~/.ssh/id_ed25519_work_yubikey.pub
    IdentitiesOnly yes

# On-disk key account
Host github-personal
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
```

> **`IdentitiesOnly yes` needs an `IdentityFile` — even for the agent key.** With
> `IdentitiesOnly yes` set, SSH only offers keys named by an `IdentityFile`
> directive. If the YubiKey host block has `IdentityAgent` but **no**
> `IdentityFile`, SSH ignores the agent, falls back to your on-disk `id_*` keys, and
> you get `Permission denied (publickey)` even though `ssh-add -L` clearly shows the
> card key. Export the card's public key to a file so it can be named:
>
> ```zsh
> ssh-add -L | grep 'cardno:' > ~/.ssh/id_ed25519_work_yubikey.pub
> ```
>
> The `.pub` holds no secret — it just tells SSH which agent key to offer.

Clone or set remotes with the alias, e.g. `git@github-work:org/repo.git` or
`git@github-personal:org/repo.git`. `IdentitiesOnly yes` stops SSH from offering
the wrong key first.

## A7 — Git commit signing

```zsh
git config --global user.signingkey <sign-subkey-id>!
git config --global commit.gpgsign true
git config --global gpg.format openpgp
```

> The trailing `!` pins the exact subkey. Find the Sign subkey ID in
> `gpg --list-secret-keys --keyid-format long` (the `ssb` line marked `[S]`).

Upload your **public** key to **every** account that verifies signatures —
GitHub, GitLab, etc. Unlike the SSH auth key, GPG has no uniqueness rule: the
**same** GPG key goes on all your accounts, and commit signatures verify on
each. You upload the **primary** key (it carries the subkeys):

```zsh
gpg --armor --export <key-id>    # add under GitHub → Settings → SSH and GPG keys → New GPG key
```

> **It goes under "GPG keys", not "SSH keys".** They share a settings page but are
> separate lists — pasting a GPG block into the SSH box silently does nothing. And
> the green **Verified** badge needs two things beyond the upload: the key on the
> account, _and_ your committer email (`user.email`) matching a UID on that key.
> Local signing (`git commit -S`) works regardless; the badge is GitHub-side.

> **What the card asks for when it signs.** The prompt is the **OpenPGP User PIN**
> (secret #2) plus a physical **touch** — not the Admin PIN, not an on-disk
> passphrase, not the FIDO2 PIN. The PIN is cached by gpg-agent per the TTLs in A6;
> the touch has its own ~15 s `cached` grace, so a burst of commits shares one
> touch. Exhausting the User PIN (8 tries) is recoverable: `gpg --card-edit` →
> `admin` → `passwd` resets it with the Admin PIN. Only exhausting the **Admin** PIN
> is fatal (`ykman openpgp reset` wipes the applet).

> **Signing the right identity per account.** `~/.ssh/config` controls SSH
> transport; committer email and signing key are git config. Route them per account
> with `includeIf` in `~/.config/git/config`:
>
> ```
> [includeIf "hasconfig:remote.*.url:git@github-work:**/**"]
>     path = ~/.config/git/work
> ```
>
> where `~/.config/git/work` sets `[user] email` + `signingkey` and `[commit]
gpgsign`. The `**/**` matters: a single `**` does **not** match the scp-style
> remote `git@github-work:org/repo.git`, because `**` is anchored to `/`-delimited
> path components and there's no `/` after the `:`. Use `**/**` (or `git@alias:*`).
> Needs git ≥ 2.36, and the block only applies once a matching remote exists.

## A8 — Verify Key #1

```zsh
ykman info                                   # applets enabled as intended
ykman openpgp info                           # KDF on, retries 8/8/8, touch cached
gpg --card-status                            # three subkeys present on card
ssh-add -L                                   # Auth subkey offered
echo test | gpg --clearsign                  # prompts for touch + User PIN
```

**Key #1 is configured.** Proceed to Part B — still no account registration yet.

---

# Part B — Key #2 (configure only)

Remove Key #1. Insert **only Key #2**. This pass makes Key #2 an interchangeable
twin: same GPG subkeys, same hardening, its own distinct FIDO2 PIN, and the same
TOTP seeds. Still **no account registration** — Part C covers both keys at once.

## B10 — Factory reset Key #2

```zsh
ykman info
ykman openpgp reset
ykman fido reset
ykman oath reset
ykman piv reset
```

Apply the same optional interface hygiene from A2 if you did it on Key #1.

## B11 — FIDO2 PIN

Set the FIDO2 PIN (8+ characters, same reasoning as A3):

```zsh
ykman fido access change-pin
```

## B12 — Harden the OpenPGP applet (same as A4)

Enable KDF via GnuPG first (it resets PINs to defaults), then set retries and PINs:

```zsh
gpg --card-edit
# gpg/card>  admin
# gpg/card>  kdf-setup
# gpg/card>  quit
ykman openpgp access set-retries 8 8 8
ykman openpgp access change-admin-pin      # set the SAME Admin PIN as Key #1
ykman openpgp access change-pin            # set the SAME User PIN as Key #1
```

> Use the **same PINs** as Key #1 so the two keys are truly interchangeable and
> there's one entry in 1Password, not two.

## B13 — Clone the GPG subkeys onto Key #2

After A5's `keytocard`, your on-disk copy is just stubs. Restore the real subkey
material from backup, then move it onto Key #2:

```zsh
# Drop the on-disk stubs (this does NOT touch Key #1's on-card keys).
gpg --delete-secret-keys <key-id>

# Re-import the subkey backup. Confirm it shows plain 'ssb', not 'ssb#'/'ssb>'.
gpg --import subkeys-only.asc
gpg --list-secret-keys --keyid-format long
```

Then repeat A5's `keytocard` flow **with Key #2 inserted**:

```zsh
gpg --expert --edit-key <key-id>
# key 1 → keytocard → 1 ; key 2 → keytocard → 2 ; key 3 → keytocard → 3 ; save
```

Set the same touch policy:

```zsh
ykman openpgp keys set-touch sig cached
ykman openpgp keys set-touch dec cached
ykman openpgp keys set-touch aut cached
```

> **One key inserted at a time.** GPG tracks which card serial a stub points at.
> When you swap between Key #1 and Key #2 later, re-sync with:
>
> ```zsh
> gpg-connect-agent "scd serialno" "learn --force" /bye
> ```

## B14 — Verify Key #2 and swap-test

```zsh
ykman openpgp info      # KDF on, 8/8/8, touch cached — matches Key #1
gpg --card-status       # same three subkeys, different card serial
ssh-add -L              # same ssh-ed25519 line as Key #1
```

> Because Key #2 carries the **same** auth subkey, its `ssh-add -L` output is
> identical to Key #1's — so the `IdentityFile ~/.ssh/id_ed25519_work_yubikey.pub`
> line from A6 works unchanged, and nothing needs re-registering on GitHub.

Test the swap: unplug Key #1, plug in Key #2, run
`gpg-connect-agent "scd serialno" "learn --force" /bye`, then
`echo test | gpg --clearsign` — it should prompt for touch + the same User PIN
and succeed.

**Both keys are now built and interchangeable** for GPG and SSH. They are not yet
on any account — that's Part C.

---

# Part C — Register both keys to accounts

Now that both keys are fully configured, add them back. Work the account list you
parked in Part 0. Because FIDO2 credentials are non-cloneable, security-key
registration is manual and per-account, done once per key.

## C1 — FIDO2 / security-key accounts

For each account that supports security keys (GitHub, AWS, Google, Auth0, and —
most importantly — your **password manager's own login**), register **both**
keys:

- In the account's 2FA settings, "Add security key" with Key #1 inserted, then
  again with Key #2. Both must be enrolled or losing one locks you out of that
  account.
- Give them distinguishable names (e.g. `yubikey-1`, `yubikey-2`).

## C2 — Top-value TOTP-only accounts (optional, on the key)

For a **handful of top-value** TOTP-only accounts you want hardware-held, put the
seed on both keys now, in one sitting. In **Yubico Authenticator**:

- Insert Key #1, add the account (scan the QR or paste the secret) when it offers
  "authenticator app" 2FA.
- Swap to Key #2 and add the **same** seed. Seeds can't be copied off a key, so
  each key is enrolled separately from the same QR/secret — same seed, same codes.

Each key holds only ~32 such credentials, so keep this list short. Everything else
stays in the authenticator app (C3).

## C3 — The rest stay in the authenticator app

Every other TOTP-only account keeps its seed in your dedicated authenticator app
(Aegis / 2FAS / Ente). Nothing goes on the key. Keep it **out of the password
manager** so the second factor stays separate from the password.

## C4 — Offline recovery codes

For every account that issues recovery/backup codes, generate a fresh set and
store them **offline** — printed, in a safe or safe-deposit box. Never a
screenshot, never synced to the cloud, never in the password vault. This plus the
second registered key is your anti-lockout net if both YubiKeys are lost.

Once an account has both keys (and/or its permanent authenticator) plus recovery
codes, **remove the temporary 2FA** you parked in Part 0.

---

## Next: the Arch install

With both keys provisioned, the main guide's optional YubiKey steps will work:

- [Step 2 — FIDO2 LUKS enrollment](./README.md#step-2--partition-encrypt-and-set-up-btrfs): enroll each key to unlock the encrypted disk.
- [Step 10 — Wire up hardware keys for GPG/SSH](./README.md#step-10--optional-wire-up-hardware-keys-gpg--ssh): the on-Linux side of what you just set up on macOS.
