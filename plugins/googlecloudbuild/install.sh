#!/usr/bin/env bash
# Cloudanix Image Scanner for Google Cloud Build — one-line setup.
#
#   curl -fsSL https://install.cloudanix.com/plugins/googlecloudbuild/install.sh | bash -s -- \
#     --project <gcp-project-id> \
#     --service-account <cloud-build-service-account-email> \
#     --identifier <cloudanix-account-identifier>
#
# What it does, in your GCP project:
#   1. Stores your Cloudanix credentials in the Secret Manager secret
#      `cdx_auth_config` (creates it, or adds a new version if it exists).
#   2. Grants the Cloud Build service account access to that secret and the
#      roles the scanner step needs.
#
# The Cloudanix auth token is NEVER a command-line argument: it is read from a
# hidden prompt (or the CDX_AUTHZ_TOKEN env var for automation), so it does not
# land in shell history, the process list, or a script file on disk. It is piped
# straight into `gcloud` on stdin.
#
# Re-running the same command is the upgrade path: every step is idempotent.
# Press Enter at the token prompt to keep the stored credentials and only
# re-apply the permissions.
#
# Options:
#   --project ID             GCP project that runs Cloud Build           (required)
#   --service-account EMAIL  Cloud Build service account                 (required)
#   --identifier ID          Cloudanix account identifier (from console) (required)
#   --label-owner VALUE      `owner` label on the secret (default: cloudanix)
#   -h, --help               Show this help
#
# Env:
#   CDX_AUTHZ_TOKEN          Token for non-interactive runs (skips the prompt).
#
# Requires: gcloud (authenticated, with permission to manage Secret Manager and
# project IAM in the target project), base64. GCP Cloud Shell has both.
#
# Exit codes: 0 success, 1 usage / precondition error, 2 gcloud call failed.
#
# This script is open source (MIT). Audit at:
#   https://github.com/Cloudanix/install-scripts/blob/main/plugins/googlecloudbuild/install.sh

set -euo pipefail

SECRET_NAME="cdx_auth_config"
# secretmanager.secretAccessor is granted resource-scoped on cdx_auth_config in
# grant_permissions (least privilege); it is intentionally NOT here, since a
# project-level binding would give read access to every secret in the project.
ROLES=(
  "roles/cloudkms.cryptoKeyDecrypter"
  "roles/iam.serviceAccountUser"
  "roles/cloudbuild.workerPoolUser"
)

PROJECT=""
SERVICE_ACCOUNT=""
IDENTIFIER=""
LABEL_OWNER="cloudanix"

die() { echo "error: $1" >&2; exit "${2:-1}"; }
info() { echo "==> $*"; }

# Under `curl | bash` there is no script file to read the header from, so the help
# text is inline.
usage() {
  cat <<'EOF'
Usage: install.sh --project ID --service-account EMAIL --identifier ID [--label-owner VALUE]

Stores Cloudanix credentials in Secret Manager (cdx_auth_config) and grants the
Cloud Build service account the roles the Cloudanix image scanner step needs.
The auth token is read from a hidden prompt, or CDX_AUTHZ_TOKEN for automation.
Re-run the same command to upgrade; press Enter at the prompt to keep the token.

Source: https://github.com/Cloudanix/install-scripts/blob/main/plugins/googlecloudbuild/install.sh
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --project)         PROJECT="${2:-}"; shift 2 ;;
      --service-account) SERVICE_ACCOUNT="${2:-}"; shift 2 ;;
      --identifier)      IDENTIFIER="${2:-}"; shift 2 ;;
      --label-owner)     LABEL_OWNER="${2:-}"; shift 2 ;;
      -h|--help)         usage; exit 0 ;;
      *)                 die "unknown option: $1 (see --help)" ;;
    esac
  done
}

# Values go to gcloud as quoted arguments (never eval'd); the checks below are for
# clear errors before anything is changed in the project.
validate_args() {
  [ -n "$PROJECT" ] || die "--project is required"
  [ -n "$SERVICE_ACCOUNT" ] || die "--service-account is required"
  [ -n "$IDENTIFIER" ] || die "--identifier is required"

  [[ "$PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] \
    || die "--project '$PROJECT' is not a valid GCP project ID"
  [[ "$SERVICE_ACCOUNT" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
    || die "--service-account '$SERVICE_ACCOUNT' is not a service account email"
  [[ "$IDENTIFIER" =~ ^[A-Za-z0-9_-]+$ ]] \
    || die "--identifier '$IDENTIFIER' has unexpected characters"
  [[ "$LABEL_OWNER" =~ ^[a-z0-9_-]{1,63}$ ]] \
    || die "--label-owner '$LABEL_OWNER' is not a valid GCP label value"

  command -v gcloud >/dev/null 2>&1 || die "'gcloud' is required (run this in GCP Cloud Shell or install the Cloud SDK)"
  command -v base64 >/dev/null 2>&1 || die "'base64' is required"
}

secret_exists() {
  gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1
}

# Prints the token on stdout, or nothing when the user chose to keep the stored one.
# Reads from /dev/tty because under `curl | bash` stdin is the script itself.
read_token() {
  if [ -n "${CDX_AUTHZ_TOKEN:-}" ]; then
    printf '%s' "$CDX_AUTHZ_TOKEN"
    return
  fi
  # -r /dev/tty is true even with no controlling terminal; only opening it tells.
  { : </dev/tty; } 2>/dev/null || die "no terminal to prompt for the token; set CDX_AUTHZ_TOKEN instead"

  local prompt="Paste your Cloudanix auth token (input hidden)"
  if secret_exists; then
    prompt="$prompt, or press Enter to keep the stored one"
  fi

  local token=""
  printf '%s: ' "$prompt" >/dev/tty
  IFS= read -rs token </dev/tty
  printf '\n' >/dev/tty
  printf '%s' "$token"
}

# The scanner reads cdx_auth_config as base64(JSON). The value only ever travels
# on stdin to gcloud (--data-file=-).
store_credentials() {
  local token="$1"
  # Tokens are URL/base64-safe; anything else (a stray quote, a pasted newline) would
  # corrupt the JSON below, so refuse it rather than store a broken secret.
  [[ "$token" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || die "the auth token has unexpected characters; copy it again from the console"

  local payload
  payload="$(printf '{"authZToken":"%s","identifier":"%s"}' "$token" "$IDENTIFIER" | base64 | tr -d '\n')"

  if secret_exists; then
    info "Adding a new version to secret $SECRET_NAME"
    printf '%s' "$payload" | gcloud secrets versions add "$SECRET_NAME" \
      --project="$PROJECT" --data-file=- >/dev/null || die "could not add secret version" 2
  else
    info "Creating secret $SECRET_NAME"
    printf '%s' "$payload" | gcloud secrets create "$SECRET_NAME" \
      --project="$PROJECT" --data-file=- --replication-policy=automatic \
      --labels="owner=$LABEL_OWNER" >/dev/null || die "could not create secret" 2
  fi
}

grant_permissions() {
  local member="serviceAccount:$SERVICE_ACCOUNT"

  info "Granting $SERVICE_ACCOUNT access to secret $SECRET_NAME"
  gcloud secrets add-iam-policy-binding "$SECRET_NAME" --project="$PROJECT" \
    --role="roles/secretmanager.secretAccessor" --member="$member" --condition=None >/dev/null \
    || die "could not grant secret access" 2

  local role
  for role in "${ROLES[@]}"; do
    info "Granting $role on project $PROJECT"
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="$member" --role="$role" --condition=None >/dev/null \
      || die "could not grant $role" 2
  done
}

main() {
  parse_args "$@"
  validate_args

  local token
  token="$(read_token)"

  if [ -n "$token" ]; then
    store_credentials "$token"
  elif secret_exists; then
    info "Keeping the stored credentials in $SECRET_NAME"
  else
    die "an auth token is required for the first setup"
  fi
  unset token

  grant_permissions
  info "Done. Add the Cloudanix scanner step to your cloudbuild.yaml (see the Cloudanix console)."
}

main "$@"
