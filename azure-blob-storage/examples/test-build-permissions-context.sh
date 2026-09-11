#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/values.yaml" <<'YAML'
resource_group_name: "rg-blob-test"
location: "eastus"
tfstate_storage_account: "npstatetest"
tfstate_resource_group: "rg-state-test"
tfstate_container: "service-tfstate"
YAML

# load_link <jq_patch> — runs build_context then build_permissions_context and
# echoes the resulting environment.
load_link() {
  local patch="${1:-.}"
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH"
    export AZ_STUB_LOG="$TMP/az.log" NP_STUB_LOG="$TMP/np.log"
    CONTEXT=$(jq "$patch" <(jq '.notification' "$SCRIPT_DIR/link.json"))
    export CONTEXT
    LINK=$(echo "$CONTEXT" | jq '.link')
    export LINK
    export SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=link NP_DRY_RUN=true
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_permissions_context" >/dev/null 2>&1
    for v in OUTPUT_DIR TOFU_MODULE_DIR TOFU_INIT_VARIABLES TOFU_VARIABLES; do
      printf '%s=%s\n' "$v" "${!v:-}"
    done
  )
}

get() { printf '%s' "$1" | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "== link action =="
ENV_OUT=$(load_link)

assert_contains "$(get "$ENV_OUT" TOFU_MODULE_DIR)" "/permissions" "module dir points at permissions/"
assert_contains "$(get "$ENV_OUT" OUTPUT_DIR)" "np-link-eeeeeeee" "output dir is per link"

echo "== link state key is nested under the service container =="
BACKEND="$(get "$ENV_OUT" OUTPUT_DIR)/backend.hcl"
assert_eq "yes" "$([ -f "$BACKEND" ] && echo yes || echo no)" "backend.hcl written into OUTPUT_DIR"
BH=$(cat "$BACKEND" 2>/dev/null)
assert_contains "$BH" 'container_name       = "service-tfstate"' "reuses the shared tfstate container"
assert_contains "$BH" 'key                  = "azure-blob-storage/9f8e7d6c-1234-4321-abcd-000000000000/links/eeeeeeee-1111-2222-3333-444444444444.tfstate"' "per-link state key nested under the service prefix"
assert_contains "$BH" 'use_azuread_auth     = true' "backend authenticates via Azure AD, not shared key"

echo "== tfvars match the permissions module variables exactly =="
TFVARS=$(get "$ENV_OUT" TOFU_VARIABLES)
assert_eq "ok" "$(printf '%s' "$TFVARS" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)" "TOFU_VARIABLES is valid JSON"
EXPECTED_KEYS="access_level container_name link_id resource_group_name sas_ttl_days storage_account_name"
assert_eq "$EXPECTED_KEYS" "$(printf '%s' "$TFVARS" | jq -r 'keys | join(" ")')" "no extra or missing keys"
assert_eq "mediaassets9f8e7d6c" "$(printf '%s' "$TFVARS" | jq -r '.storage_account_name')" "account name read from service attributes"
assert_eq "rg-blob-test" "$(printf '%s' "$TFVARS" | jq -r '.resource_group_name')" "resource group read from service attributes"
assert_eq "media-uploads" "$(printf '%s' "$TFVARS" | jq -r '.container_name')" "container name from link parameters"
assert_eq "read-write" "$(printf '%s' "$TFVARS" | jq -r '.access_level')" "access level mapped from accessLevel"
assert_eq "30" "$(printf '%s' "$TFVARS" | jq -r '.sas_ttl_days')" "sas ttl from link parameters"
assert_eq "number" "$(printf '%s' "$TFVARS" | jq -r '.sas_ttl_days | type')" "sas_ttl_days typed as number"

echo "== missing account_name is a clear, actionable error =="
ERR=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az2.log" NP_STUB_LOG="$TMP/np2.log"
  CONTEXT=$(jq '.notification | .service.attributes = {}' "$SCRIPT_DIR/link.json")
  export CONTEXT
  LINK=$(echo "$CONTEXT" | jq '.link'); export LINK
  export SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=link NP_DRY_RUN=true
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_permissions_context" 2>&1
) || true
assert_contains "$ERR" "account_name" "error names the missing attribute"
assert_contains "$ERR" "create" "error points at the incomplete create action"

echo "== invalid container names are rejected =="
reject_container() {
  local name="$1" label="$2"
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az3.log" NP_STUB_LOG="$TMP/np3.log"
    CONTEXT=$(jq --arg n "$name" '.notification | .parameters.container_name = $n' "$SCRIPT_DIR/link.json")
    export CONTEXT
    LINK=$(echo "$CONTEXT" | jq '.link'); export LINK
    export SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=link NP_DRY_RUN=true
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_permissions_context" >/dev/null 2>&1
  ) && { echo "  FAIL $label" >&2; FAILURES=$((FAILURES + 1)); } || echo "  ok   $label"
}
reject_container "ab"                    "too short rejected"
reject_container "Media-Uploads"         "uppercase rejected"
reject_container "media--uploads"        "consecutive hyphens rejected"
reject_container "-media"                "leading hyphen rejected"
reject_container "media-"                "trailing hyphen rejected"
reject_container "media_uploads"         "underscore rejected"
reject_container "../../etc/passwd"      "path traversal rejected"

echo "== unlink without a container name exits cleanly =="
UNLINK_OUT=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az4.log" NP_STUB_LOG="$TMP/np4.log"
  CONTEXT=$(jq '.notification | .type = "delete" | .parameters = {} | .link.attributes = {}' "$SCRIPT_DIR/link.json")
  export CONTEXT
  LINK=$(echo "$CONTEXT" | jq '.link'); export LINK
  export SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=link NP_DRY_RUN=true
  # build_permissions_context calls "exit 0" on this branch, which ends this
  # subshell immediately — a trap is the only way to still observe the
  # variables it exported right before exiting.
  trap 'printf "NP_SKIP_TOFU=%s\nTOFU_MODULE_DIR=%s\n" "${NP_SKIP_TOFU:-}" "${TOFU_MODULE_DIR:-}"' EXIT
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_permissions_context" 2>&1
) && UNLINK_RC=0 || UNLINK_RC=$?
assert_eq "0" "$UNLINK_RC" "unlink with no container name does not fail the workflow"
assert_contains "$UNLINK_OUT" "never fully created" "explains that there is nothing to destroy"

# --- C1: the early exit must neutralise the Terraform context, not just return ---
assert_eq "true" "$(get "$UNLINK_OUT" NP_SKIP_TOFU)" \
  "NP_SKIP_TOFU is set so do_tofu and write_link_outputs no-op instead of running tofu destroy"

UNLINK_MODULE_DIR="$(get "$UNLINK_OUT" TOFU_MODULE_DIR)"
case "$UNLINK_MODULE_DIR" in
  */deployment)
    echo "  FAIL TOFU_MODULE_DIR still points at deployment/ (got: '$UNLINK_MODULE_DIR') — the next" >&2
    echo "       step (do_tofu) would see this and could destroy the Storage Account" >&2
    FAILURES=$((FAILURES + 1))
    ;;
  *)
    echo "  ok   TOFU_MODULE_DIR does not point at deployment/ (got: '$UNLINK_MODULE_DIR')"
    ;;
esac

finish_tests
