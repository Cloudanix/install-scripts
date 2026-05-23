# Cloudanix Installers

One-line installers for Cloudanix products. Served at
**[install.cloudanix.com](https://install.cloudanix.com)**.

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard \
  | CLOUDANIX_INSTALL_TOKEN="ghp_…" bash
```

> **Env vars go on the `bash` side of the pipe**, not on `curl`. Vars
> set before `curl` don't propagate through the pipe (a classic
> curl-pipe-bash gotcha).

This repository is the **public, MIT-licensed source** of every
installer Cloudanix asks customers to run. The products they install
live in their own repositories and carry their own licenses.

---

## Why open-source the installers?

1. **Auditability is the trust contract for `curl | bash`.** A customer
   pasting our URL into a browser before running the command should be
   able to read every line.
2. **Pinned-version installs need a public git history.** Customers
   running an older release can compare diffs.
3. **No product IP is exposed.** Installers orchestrate a download from
   a Cloudanix-controlled artefact store. Customers provide their own
   auth token; secrets are never written into the scripts.

---

## Products

| Product            | URL                                          |
|--------------------|----------------------------------------------|
| Cloudanix Guard    | `install.cloudanix.com/cloudanix-guard`      |

---

## How a customer installs Cloudanix Guard

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard \
  | CLOUDANIX_INSTALL_TOKEN="ghp_…" bash
```

What that does (paraphrased from the [script itself](./cloudanix-guard)):

1. Verifies Python ≥ 3.9 and `curl` are available.
2. Resolves the latest release from the Cloudanix Guard release page.
3. Downloads the wheel using the customer's `CLOUDANIX_INSTALL_TOKEN`.
4. Creates a venv at `~/.cloudanix-guard/venv` (or reuses one).
5. `pip install`s the wheel into that venv.
6. Drops a stable launcher shim at
   `~/.cloudanix-guard/bin/cloudanix-guard` so subsequent upgrades
   don't invalidate paths registered with other tools.
7. Prints next-step instructions.

### Pin a version

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard \
  | CLOUDANIX_INSTALL_TOKEN="ghp_…" CLOUDANIX_VERSION="0.1.0" bash
```

### Get an install token

Customers receive an install token from their Cloudanix administrator
or via the Cloudanix Console.

---

## Security posture

- **Installer is MIT-licensed.** Inspect, fork, port — no restrictions.
- **Downloads are TLS-authenticated.** The script verifies the response
  shape before installing.
- **No secrets in the script.** `CLOUDANIX_INSTALL_TOKEN` is read from
  the environment, used only as an HTTP `Authorization` header, and
  never written to disk, logged, or echoed.
- **No `sudo`.** Default install is under `$HOME`.
- **No persistent shell modifications.** The script prints `export PATH=…`
  guidance but never edits `~/.bashrc` / `~/.zshrc` for you.
- **Strict mode + ShellCheck on CI** — `set -euo pipefail`; no
  unguarded `command-not-found`; no implicit word-split bugs.

Found a bug? Open an issue on this repo. For sensitive disclosures
contact `security@cloudanix.com`.

---

## License

The installer scripts in this repository are MIT-licensed
([LICENSE](./LICENSE)). The Cloudanix products they install carry
their own licenses, which you accept on first run.
