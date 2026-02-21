#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "SUPABASE_ACCESS_TOKEN is required"
  exit 1
fi
if [[ "${SUPABASE_ACCESS_TOKEN}" == "your-supabase-personal-access-token" ]]; then
  echo "SUPABASE_ACCESS_TOKEN is still set to the placeholder value."
  echo "Create a real token at https://supabase.com/dashboard/account/tokens and export it."
  exit 1
fi

if [[ -z "${PROJECT_REF:-}" || "${PROJECT_REF}" == "<project-ref>" ]]; then
  echo "PROJECT_REF is required"
  exit 1
fi

PROJECT_REF="${PROJECT_REF}"
PATCH_FILE="${1:-${ROOT_DIR}/scripts/supabase/admin/auth_email_templates_patch.json}"
BACKUP_FILE="${ROOT_DIR}/scripts/supabase/fixtures/backups/auth_email_templates_backup_$(date +%Y%m%d_%H%M%S).json"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "Patch file not found: $PATCH_FILE"
  exit 1
fi

tmp_get="$(mktemp)"
tmp_patch="$(mktemp)"
trap 'rm -f "$tmp_get" "$tmp_patch"' EXIT

echo "Backing up current mailer settings to $BACKUP_FILE"
get_status="$(
  curl -sS -o "$tmp_get" -w "%{http_code}" -X GET "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}"
)"
if [[ "$get_status" -lt 200 || "$get_status" -ge 300 ]]; then
  echo "GET /config/auth failed with HTTP $get_status"
  cat "$tmp_get"
  echo
  exit 1
fi

jq 'to_entries | map(select(.key | startswith("mailer_"))) | from_entries' "$tmp_get" > "$BACKUP_FILE"

echo "Applying updated templates from $PATCH_FILE"
patch_status="$(
  curl -sS -o "$tmp_patch" -w "%{http_code}" -X PATCH "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@$PATCH_FILE"
)"
if [[ "$patch_status" -lt 200 || "$patch_status" -ge 300 ]]; then
  echo "PATCH /config/auth failed with HTTP $patch_status"
  cat "$tmp_patch"
  echo
  exit 1
fi

echo "Done. Current subjects:"
curl -sS -X GET "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  | jq '{mailer_subjects_confirmation, mailer_subjects_recovery, mailer_templates_confirmation_content, mailer_templates_recovery_content}'
