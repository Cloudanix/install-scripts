# Cloudanix Installers

One-line installers for Cloudanix products. Served at
**[install.cloudanix.com](https://install.cloudanix.com)**.

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard | bash
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
   a public Cloudanix-controlled artefact mirror
   ([`Cloudanix/artifacts`](https://github.com/Cloudanix/artifacts))
   and verify a SHA256 sidecar before installing. No secrets in
   scripts; no per-customer tokens to manage.

---

## Products

| Product            | URL                                          |
|--------------------|----------------------------------------------|
| Cloudanix Guard    | `install.cloudanix.com/cloudanix-guard`      |

---

## How a customer installs Cloudanix Guard

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard | bash
```

What that does (paraphrased from the [script itself](./cloudanix-guard)):

1. Verifies `curl` and `tar` are available and detects your OS/arch.
2. Downloads the matching release archive
   (`cloudanix-guard_<version>_<os>_<arch>.tar.gz`) + its SHA256
   sidecar from
   `github.com/Cloudanix/artifacts/raw/main/coding-agent-guard/`.
3. Verifies the archive against its SHA256 — aborts on mismatch.
4. Extracts the self-contained `cloudanix-guard` binary — no Python,
   no runtime to manage.
5. Installs it at the stable path
   `~/.cloudanix-guard/bin/cloudanix-guard`, so upgrades replace the
   binary in place and never invalidate paths other tools have
   registered (e.g. Codex's hook trust-hash).
6. Prints next-step instructions, including how to wire the guard
   into Claude Code / Codex / Kiro.

### Pin a version

```bash
curl -fsSL https://install.cloudanix.com/cloudanix-guard \
  | CLOUDANIX_VERSION="0.1.1" bash
```

The named version must exist in `Cloudanix/artifacts/coding-agent-guard/`
as `cloudanix-guard_<version>_<os>_<arch>.tar.gz` (with a matching
`.sha256` sidecar) for your platform. Otherwise the installer aborts
with a 404 from the artifact CDN.

---

## Security posture

- **Installer is MIT-licensed.** Inspect, fork, port — no restrictions.
- **Binary integrity is verified.** Each release archive ships a
  `.sha256` sidecar published alongside it; the installer downloads
  both and aborts on mismatch.
- **No secrets in the script.** No GitHub tokens, no API keys,
  nothing read from the environment that touches an auth header.
- **No `sudo`.** Default install is under `$HOME`.
- **No persistent shell modifications.** The script prints
  `export PATH=…` guidance but never edits `~/.bashrc` / `~/.zshrc`
  for you.
- **Strict mode + ShellCheck on CI** — `set -euo pipefail`; no
  unguarded `command-not-found`; no implicit word-split bugs.
- **Dev-only env-var overrides are gated** behind
  `CLOUDANIX_INSTALL_DEV=1`. Without that flag, the overrides
  (`CLOUDANIX_LOCAL_LIB`, `CLOUDANIX_LOCAL_BINARY`,
  `CLOUDANIX_LOCAL_TARBALL`, `CLOUDANIX_INSTALL_BASE`,
  `CLOUDANIX_ARTIFACTS_URL`) refuse to apply — closes a phishing path
  where someone tricks a developer into pasting
  `CLOUDANIX_LOCAL_BINARY=/tmp/evil curl … | bash`.

Found a bug? Open an issue on this repo. For sensitive disclosures
contact `security@cloudanix.com`.

---

## License

The installer scripts in this repository are MIT-licensed
([LICENSE](./LICENSE)). The Cloudanix products they install carry
their own licenses, which you accept on first run.
