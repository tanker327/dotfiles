# vps/db Docker test

Self-contained smoke test for `vps/db/setup-postgres.sh`. Runs the installer
inside an `ubuntu:24.04` container, then asserts the result.

## Run

```bash
bash vps/db/test/run-test.sh
```

Expected final output: `ALL CHECKS PASSED`.

The script builds an image from the **current working tree** of the repo (not
git HEAD), so edits to `setup-postgres.sh` are picked up immediately.

## What it covers

- Installer completes on a clean Ubuntu 24.04
- Service starts; `appdb` and `appuser` are created
- `appuser` can connect over TCP with the generated password
- `shared_buffers`, `listen_addresses=*`, `ssl=off`, `password_encryption=scram-sha-256` are applied
- Daily backup script produces a valid gzipped `pg_dumpall`
- `/etc/cron.d/postgres-backup` is installed
- `pg_hba.conf` has the `0.0.0.0/0 scram-sha-256` host rule
- Credentials files (`/root/postgres-setup-info.txt`, `/root/.postgres-setup-state`) are mode 600
- Re-running the installer is idempotent (every step skips)
- `configure-s3-backup.sh status` reports `NOT CONFIGURED`

## What it doesn't cover

- **Real S3 upload.** The default test answers `n` to the S3 prompt, so the
  AWS CLI and S3 codepath are not exercised. To test S3 manually:

  1. Edit `run-test.sh` to answer `y` and supply bucket/region/keys, **or**
  2. Inside a built container, run `configure-s3-backup.sh enable` against a
     real bucket (or a MinIO sidecar with
     `AWS_ENDPOINT_URL=http://minio:9000`).

- **UFW**. The test container doesn't run UFW, so the installer logs a
  warning and skips the firewall step. On a real VPS the rule is added.

- **`systemctl`**. The container has no systemd; a shim at
  `/usr/local/bin/systemctl` translates `systemctl <verb> postgresql` to
  `pg_ctlcluster`. The installer itself is unmodified.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Ubuntu 24.04 base + minimal prereqs; copies the repo into `/root/dotfiles` and installs the systemctl shim. |
| `systemctl-shim.sh` | Translates `systemctl` to `pg_ctlcluster` inside the container. Test-only. |
| `run-test.sh` | Builds the image, runs the installer non-interactively, runs assertions. |
