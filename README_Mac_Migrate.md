[README.md](https://github.com/user-attachments/files/29296759/README.md)
# mac-migrate

Portable dev-environment migration for Mac. Scans for transferable tool
configs/creds, bundles them encrypted, restores on a new machine, and runs a
test suite to prove each tool still works.

Like Linux dotfiles, but it also carries OAuth tokens/creds and verifies them.

## Quick start

**Old machine:**
```bash
./mac-migrate.sh scan        # see what will transfer; writes manifest.txt + Brewfile
# review manifest.txt, delete any line you don't want
./mac-migrate.sh bundle      # prompts for a passphrase -> mac-migrate-bundle.tar.gz.enc
```

**New machine** — copy the **whole folder** over (AirDrop/USB/scp), then one command:
```bash
./install-newmac.sh
```
That bootstrapper finds the `.enc` bundle (looks next to itself, plus Downloads,
Desktop, and mounted USB volumes), installs Homebrew if missing, runs
`brew bundle`, restores your configs/creds, reloads your shell, and runs the
test suite. Pass an explicit path if auto-detect misses it:
`./install-newmac.sh /path/to/bundle.tar.gz.enc`.

Prefer to do it by hand instead:
```bash
brew bundle --file=Brewfile
./mac-migrate.sh restore mac-migrate-bundle.tar.gz.enc   # same passphrase
exec $SHELL
./mac-migrate.sh test
```

`./mac-migrate.sh doctor` = scan + test, no bundling (quick health check).

## What it handles

git, ssh, gnupg, gam, gcloud/gsutil, gh, aws, kube, docker, rclone, npm,
terraform, vpn, shell rc files, editors. Tools not installed are skipped.
A heuristic sweep also lists stray dotfiles for you to review.

Add a tool: append one row to `CATALOG` in the script —
`name|paths|testcmd|secret`. Test cmds can't contain `|` `(` `)`; for anything
fancier add a `_t_<name>` function and reference it by name.

## Safety notes

- Bundle is AES-256 encrypted (openssl, pbkdf2). **The passphrase is the only
  protection for your OAuth tokens and SSH keys — use a strong one, share out of band.**
- `restore` backs up any file it would overwrite to `~/.mac-migrate-backup-<ts>/`.
- Absolute `/Users/<olduser>` paths inside text configs are rewritten to the new
  user's home automatically.
- Caches and machine-specific blobs (tldr cache, Cisco client binaries) are
  deliberately excluded — reinstall those fresh.
- crontab is saved to `crontab.bak` but NOT auto-installed: `crontab crontab.bak`.

## Scripted / CI use

Set `MAC_MIGRATE_PASS` to skip the interactive passphrase prompt:
```bash
MAC_MIGRATE_PASS=… ./mac-migrate.sh bundle out.enc
MAC_MIGRATE_PASS=… ./mac-migrate.sh restore out.enc
```
Override the working dir with `MAC_MIGRATE_DIR`.
