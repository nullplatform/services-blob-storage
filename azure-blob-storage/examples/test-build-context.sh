#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A values.yaml with placement filled in, so the test does not depend on the
# committed (intentionally empty) one.
cat > "$TMP/values.yaml" <<'YAML'
subscription_id: "sub-1234"
client_id: ""
tenant_id: ""
resource_group_name: "rg-blob-test"
location: "eastus"
tfstate_storage_account: "npstatetest"
tfstate_resource_group: "rg-state-test"
tfstate_container: "service-tfstate"
YAML

# load_context <fixture> — sources build_context in a subshell and echoes the
# resulting environment as KEY=VALUE lines.
load_context() {
  local fixture="$1"
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH"
    export AZ_STUB_LOG="$TMP/az.log"
    export NP_STUB_LOG="$TMP/np.log"
    export CONTEXT
    CONTEXT=$(jq '.notification' "$fixture")
    export LINK
    LINK=$(echo "$CONTEXT" | jq '.link')
    export SERVICE_PATH VALUES="$TMP/values.yaml"
    export ACTION_SOURCE
    ACTION_SOURCE=$([ "$(echo "$CONTEXT" | jq '.link != null')" = "true" ] && echo link || echo service)
    export NP_DRY_RUN=true
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
    for v in SERVICE_ID SERVICE_NAME STORAGE_ACCOUNT_NAME RESOURCE_GROUP_NAME LOCATION \
             TFSTATE_STORAGE_ACCOUNT TFSTATE_RESOURCE_GROUP TFSTATE_CONTAINER \
             OUTPUT_DIR TOFU_MODULE_DIR TOFU_INIT_VARIABLES TOFU_VARIABLES; do
      printf '%s=%s\n' "$v" "${!v:-}"
    done
  )
}

get() { printf '%s' "$1" | grep "^$2=" | head -1 | cut -d= -f2-; }

echo "== create action =="
ENV_OUT=$(load_context "$SCRIPT_DIR/create.json")

assert_eq "9f8e7d6c-1234-4321-abcd-000000000000" "$(get "$ENV_OUT" SERVICE_ID)" "SERVICE_ID parsed"
assert_eq "mediaassets9f8e7d6c" "$(get "$ENV_OUT" STORAGE_ACCOUNT_NAME)" "storage account name derived from service name"
assert_eq "rg-blob-test" "$(get "$ENV_OUT" RESOURCE_GROUP_NAME)" "resource group from values.yaml"
assert_eq "eastus" "$(get "$ENV_OUT" LOCATION)" "location from values.yaml"
assert_eq "service-tfstate" "$(get "$ENV_OUT" TFSTATE_CONTAINER)" "usa el container compartido, no crea uno"
assert_eq "rg-state-test" "$(get "$ENV_OUT" TFSTATE_RESOURCE_GROUP)" "tfstate resource group from values.yaml"
assert_contains "$(get "$ENV_OUT" TOFU_MODULE_DIR)" "/deployment" "module dir points at deployment/"
assert_contains "$(get "$ENV_OUT" OUTPUT_DIR)" "np-service-9f8e7d6c" "output dir is per service instance"

echo "== backend settings are written as a FILE, never as a flag string =="
# A flag string has to cross the workflow engine's environment channel and be
# word-split back into argv; one added quote turns a flag into a positional
# argument and tofu answers "Unexpected argument".
BACKEND="$(get "$ENV_OUT" OUTPUT_DIR)/backend.hcl"
assert_eq "yes" "$([ -f "$BACKEND" ] && echo yes || echo no)" "backend.hcl written into OUTPUT_DIR"
BH=$(cat "$BACKEND" 2>/dev/null)
assert_contains "$BH" 'storage_account_name = "npstatetest"' "state account"
assert_contains "$BH" 'container_name       = "service-tfstate"' "state container"
assert_contains "$BH" 'key                  = "azure-blob-storage/9f8e7d6c-1234-4321-abcd-000000000000/deployment.tfstate"' "per-service state key"
assert_contains "$BH" 'resource_group_name  = "rg-state-test"' "state resource group"
assert_contains "$BH" 'use_azuread_auth     = true' "backend authenticates via Azure AD, not shared key"
assert_eq "" "$(get "$ENV_OUT" TOFU_INIT_VARIABLES)" "no flag string is exported any more"

echo "== TOFU_VARIABLES is a JSON object matching the module's variables =="
TFVARS=$(get "$ENV_OUT" TOFU_VARIABLES)
assert_eq "ok" "$(printf '%s' "$TFVARS" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)" "TOFU_VARIABLES is valid JSON"
assert_eq "mediaassets9f8e7d6c" "$(printf '%s' "$TFVARS" | jq -r '.storage_account_name')" "tfvars storage_account_name"
assert_eq "ZRS" "$(printf '%s' "$TFVARS" | jq -r '.replication_type')" "parameters override attributes"
assert_eq "14" "$(printf '%s' "$TFVARS" | jq -r '.soft_delete_days')" "numeric parameter is a JSON number"
assert_eq "number" "$(printf '%s' "$TFVARS" | jq -r '.soft_delete_days | type')" "soft_delete_days typed as number"
assert_eq "boolean" "$(printf '%s' "$TFVARS" | jq -r '.blob_versioning | type')" "blob_versioning typed as boolean"
assert_eq "true" "$(printf '%s' "$TFVARS" | jq -r '.blob_versioning')" "blob_versioning value"
assert_eq "object" "$(printf '%s' "$TFVARS" | jq -r '.tags | type')" "tags typed as object"

echo "== tfvars keys are exactly the module's variables =="
EXPECTED_KEYS="access_tier account_tier blob_versioning container_soft_delete_days location replication_type resource_group_name service_id soft_delete_days storage_account_name tags"
assert_eq "$EXPECTED_KEYS" "$(printf '%s' "$TFVARS" | jq -r 'keys | join(" ")')" "no extra or missing tfvars keys"

echo "== nada invoca az: el bootstrap de container ya no existe ==
"
if grep -q "az storage" "$SERVICE_PATH/scripts/azure/build_context"; then
  echo "  FAIL build_context sigue llamando a az" >&2; FAILURES=$((FAILURES + 1))
else
  echo "  ok   build_context no depende del binario az"
fi

echo "== attributes are merged with parameters, parameters winning =="
MERGED=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az2.log" NP_STUB_LOG="$TMP/np2.log"
  CONTEXT=$(jq '.notification
    | .service.attributes = {"replication_type":"LRS","access_tier":"Cool"}
    | .parameters = {"replication_type":"GZRS"}' "$SCRIPT_DIR/create.json")
  export CONTEXT
  export LINK=null SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=service NP_DRY_RUN=true
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
  printf '%s' "$TOFU_VARIABLES"
)
assert_eq "GZRS" "$(printf '%s' "$MERGED" | jq -r '.replication_type')" "parameter beats stored attribute"
assert_eq "Cool" "$(printf '%s' "$MERGED" | jq -r '.access_tier')" "stored attribute used when no parameter"

echo "== a stored account_name is stable and wins over a changed .service.name (C3/I1) =="
# "name" forces replacement on azurerm_storage_account: recomputing the name
# from .service.name on every action would destroy the account and its data
# the moment someone renames the service instance in nullplatform.
STABLE_NAME_ENV=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az5.log" NP_STUB_LOG="$TMP/np5.log"
  CONTEXT=$(jq '.notification
    | .service.name = "Totally Renamed Service"
    | .service.attributes = {"account_name":"mediaassets9f8e7d6c"}' "$SCRIPT_DIR/create.json")
  export CONTEXT LINK=null SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=service NP_DRY_RUN=true
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
  printf 'STORAGE_ACCOUNT_NAME=%s\n' "$STORAGE_ACCOUNT_NAME"
)
assert_eq "STORAGE_ACCOUNT_NAME=mediaassets9f8e7d6c" "$STABLE_NAME_ENV" \
  "stored account_name wins over a freshly-computed name from the changed service name"

echo "== invalid parameters are rejected =="
reject() {
  local patch="$1" label="$2"
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az3.log" NP_STUB_LOG="$TMP/np3.log"
    CONTEXT=$(jq --argjson p "$patch" '.notification | .parameters = $p' "$SCRIPT_DIR/create.json")
    export CONTEXT LINK=null SERVICE_PATH VALUES="$TMP/values.yaml" ACTION_SOURCE=service NP_DRY_RUN=true
    # shellcheck source=/dev/null
    source "$SERVICE_PATH/scripts/azure/build_context" >/dev/null 2>&1
  ) && { echo "  FAIL $label" >&2; FAILURES=$((FAILURES + 1)); } || echo "  ok   $label"
}
reject '{"account_tier":"Deluxe"}'          "unknown account_tier rejected"
reject '{"replication_type":"XYZ"}'         "unknown replication_type rejected"
reject '{"access_tier":"Lukewarm"}'         "unknown access_tier rejected"
reject '{"soft_delete_days":"; rm -rf /"}'  "non-numeric soft_delete_days rejected"
reject '{"soft_delete_days":9999}'          "out-of-range soft_delete_days rejected"

echo "== missing placement fails with a clear message =="
EMPTY_VALUES="$TMP/empty-values.yaml"
printf 'subscription_id: ""\nresource_group_name: ""\nlocation: ""\ntfstate_storage_account: ""\n' > "$EMPTY_VALUES"
PLACEMENT_ERR=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH" AZ_STUB_LOG="$TMP/az4.log" NP_STUB_LOG="$TMP/np4.log"
  CONTEXT=$(jq '.notification' "$SCRIPT_DIR/create.json")
  export CONTEXT LINK=null SERVICE_PATH VALUES="$EMPTY_VALUES" ACTION_SOURCE=service NP_DRY_RUN=true
  # shellcheck source=/dev/null
  source "$SERVICE_PATH/scripts/azure/build_context" 2>&1
) || true
assert_contains "$PLACEMENT_ERR" "resource_group_name" "error names the missing setting"

finish_tests
