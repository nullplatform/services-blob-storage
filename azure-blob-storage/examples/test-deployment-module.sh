#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

MODULE="$SERVICE_PATH/deployment"

if ! command -v tofu >/dev/null 2>&1; then
  echo "  skip tofu not installed, skipping module validation"
  finish_tests
  exit 0
fi

echo "== formatting =="
assert_eq "formatted" "$(tofu fmt -check -recursive "$MODULE" >/dev/null 2>&1 && echo formatted || echo unformatted)" "tofu fmt -check passes"

echo "== init and validate =="
tofu -chdir="$MODULE" init -backend=false -input=false >/dev/null 2>&1 || true
VALIDATE_OUT=$(tofu -chdir="$MODULE" validate 2>&1) && VALIDATE_RC=0 || VALIDATE_RC=$?
assert_eq "0" "$VALIDATE_RC" "tofu validate succeeds"
if [ "$VALIDATE_RC" -ne 0 ]; then
  echo "$VALIDATE_OUT" >&2
fi

echo "== the module takes typed variables, not a context blob =="
assert_eq "absent" "$(grep -q 'variable "context"' "$MODULE/variables.tf" && echo present || echo absent)" "no var.context"
assert_eq "absent" "$(grep -q 'jsondecode' "$MODULE"/*.tf && echo present || echo absent)" "no jsondecode of a notification"
for v in service_id storage_account_name resource_group_name location account_tier \
         replication_type access_tier blob_versioning soft_delete_days \
         container_soft_delete_days tags; do
  assert_eq "present" "$(grep -q "variable \"$v\"" "$MODULE/variables.tf" && echo present || echo absent)" "variable $v declared"
done

echo "== every free-form REQUIRED string variable is validated, mirroring build_context =="
# location is deliberately absent from this list: it is optional (default "")
# and an empty value is meaningful — it means "use the resource group's own
# location". A non-empty validation there would reject the default. The
# location-is-optional contract is asserted separately below.
for v in service_id storage_account_name resource_group_name; do
  BLOCK=$(sed -n "/variable \"$v\"/,/^}/p" "$MODULE/variables.tf")
  assert_contains "$BLOCK" "validation {" "variable $v carries a validation block"
done

echo "== location is optional and falls back to the resource group =="
LOC_BLOCK=$(sed -n '/variable "location"/,/^}/p' "$MODULE/variables.tf")
assert_contains "$LOC_BLOCK" 'default     = ""' "location defaults to empty"
assert_contains "$(cat "$MODULE/main.tf")" 'data "azurerm_resource_group" "target"' \
  "main.tf reads the resource group to resolve the location"
assert_contains "$(cat "$MODULE/main.tf")" 'data.azurerm_resource_group.target.location' \
  "the fallback actually uses the resource group's location"
assert_contains "$(cat "$MODULE/main.tf")" 'location            = local.location' \
  "the storage account consumes the resolved local, not var.location directly"

echo "== provider pin matches the argument names in use =="
assert_eq "present" "$(grep -q 'version = "~> 4.0"' "$MODULE/providers.tf" && echo present || echo absent)" "azurerm pinned to ~> 4.0 (permissions/ needs storage_account_id)"
assert_eq "present" "$(grep -q 'https_traffic_only_enabled' "$MODULE/main.tf" && echo present || echo absent)" "uses the current argument name"

echo "== TLS and HTTPS are hardcoded, not variable =="
assert_eq "present" "$(grep -q 'min_tls_version *= *"TLS1_2"' "$MODULE/main.tf" && echo present || echo absent)" "min_tls_version fixed to TLS1_2"
assert_eq "present" "$(grep -q 'https_traffic_only_enabled *= *true' "$MODULE/main.tf" && echo present || echo absent)" "https_traffic_only_enabled fixed to true"
assert_eq "absent" "$(grep -q 'variable "min_tls_version"' "$MODULE/variables.tf" && echo present || echo absent)" "min_tls_version is not a variable"

echo "== account secrets are not module outputs =="
assert_eq "absent" "$(grep -q 'primary_access_key' "$MODULE/outputs.tf" && echo present || echo absent)" "primary_access_key not exposed"
assert_eq "absent" "$(grep -q 'primary_connection_string' "$MODULE/outputs.tf" && echo present || echo absent)" "primary_connection_string not exposed"

echo "== outputs the write_service_outputs step depends on =="
for o in account_name primary_blob_endpoint account_id resource_group_name; do
  assert_eq "present" "$(grep -q "output \"$o\"" "$MODULE/outputs.tf" && echo present || echo absent)" "output $o declared"
done

echo "== backend is static, azurerm, and unconfigured =="
assert_eq "present" "$(grep -q 'backend "azurerm"' "$MODULE/backend.tf" && echo present || echo absent)" "azurerm backend declared in backend.tf"

finish_tests
