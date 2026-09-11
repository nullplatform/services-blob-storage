#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

MODULE="$SERVICE_PATH/permissions"

echo "== variables match what build_permissions_context emits =="
for v in link_id storage_account_name resource_group_name container_name access_level sas_ttl_days; do
  assert_eq "present" "$(grep -q "variable \"$v\"" "$MODULE/variables.tf" 2>/dev/null && echo present || echo absent)" "variable $v declared"
done

echo "== every free-form string variable is validated, mirroring build_permissions_context =="
for v in link_id storage_account_name resource_group_name container_name; do
  BLOCK=$(sed -n "/variable \"$v\"/,/^}/p" "$MODULE/variables.tf" 2>/dev/null)
  assert_contains "$BLOCK" "validation {" "variable $v carries a validation block"
done

echo "== the access level matrix covers all three levels =="
for level in '"read"' '"write"' '"read-write"'; do
  assert_eq "present" "$(grep -q "$level" "$MODULE/locals.tf" 2>/dev/null && echo present || echo absent)" "locals map has $level"
done

echo "== read must not grant delete =="
# Extract the whole `read` block, not just its opening line: `grep -A0` returns only
# the matching line (`"read" = {`), which can never contain the block's contents.
# Normalise runs of spaces too, so the assertion does not depend on the exact column
# alignment `tofu fmt` happens to choose.
READ_BLOCK=$(sed -n '/"read" *= *{/,/^    }/p' "$MODULE/locals.tf" 2>/dev/null | tr -s ' ')
assert_contains "$READ_BLOCK" "delete = false" "read grants no delete"
assert_contains "$READ_BLOCK" "write = false" "read grants no write"
assert_contains "$READ_BLOCK" "add = false" "read grants no add"
assert_contains "$READ_BLOCK" "create = false" "read grants no create"
assert_contains "$READ_BLOCK" "read = true" "read grants read"
assert_contains "$READ_BLOCK" "list = true" "read grants list"

echo "== the SAS start is anchored in state, not recomputed =="
assert_eq "present" "$(grep -q 'resource "time_static"' "$MODULE/main.tf" 2>/dev/null && echo present || echo absent)" "time_static anchors the SAS start"
# Strip comments before grepping. The module carries a comment explaining WHY timestamp()
# was avoided, and grepping raw text makes that comment fail its own assertion.
assert_eq "absent" "$(sed 's/#.*//' "$MODULE"/*.tf 2>/dev/null | grep -q 'timestamp()' && echo present || echo absent)" "no bare timestamp() that would churn the SAS"

echo "== azurerm 4.x container API =="
assert_eq "present" "$(grep -q 'storage_account_id' "$MODULE/main.tf" 2>/dev/null && echo present || echo absent)" "container uses storage_account_id (4.x)"
assert_eq "present" "$(grep -q 'version = "~> 4.0"' "$MODULE/providers.tf" 2>/dev/null && echo present || echo absent)" "azurerm pinned ~> 4.0"
assert_eq "present" "$(grep -q 'hashicorp/time' "$MODULE/providers.tf" 2>/dev/null && echo present || echo absent)" "time provider declared"

echo "== the SAS is https-only =="
assert_eq "present" "$(grep -q 'https_only *= *true' "$MODULE/main.tf" 2>/dev/null && echo present || echo absent)" "https_only enforced"

echo "== the module reads the connection string rather than taking a secret =="
assert_eq "present" "$(grep -q 'data "azurerm_storage_account"' "$MODULE/main.tf" 2>/dev/null && echo present || echo absent)" "reads the account via a data source"
assert_eq "absent" "$(grep -q 'variable "connection_string"\|variable "account_key"' "$MODULE/variables.tf" 2>/dev/null && echo present || echo absent)" "no credential passed in as a variable"

echo "== outputs write_link_outputs depends on =="
for o in container_name sas_token blob_endpoint; do
  assert_eq "present" "$(grep -q "output \"$o\"" "$MODULE/outputs.tf" 2>/dev/null && echo present || echo absent)" "output $o declared"
done
assert_eq "present" "$(grep -A3 'output "sas_token"' "$MODULE/outputs.tf" 2>/dev/null | grep -q 'sensitive *= *true' && echo present || echo absent)" "sas_token marked sensitive"

echo "== backend is static and azurerm =="
assert_eq "present" "$(grep -q 'backend "azurerm"' "$MODULE/backend.tf" 2>/dev/null && echo present || echo absent)" "azurerm backend in backend.tf"

if command -v tofu >/dev/null 2>&1; then
  echo "== fmt, init and validate =="
  assert_eq "formatted" "$(tofu fmt -check -recursive "$MODULE" >/dev/null 2>&1 && echo formatted || echo unformatted)" "tofu fmt -check passes"
  tofu -chdir="$MODULE" init -backend=false -input=false >/dev/null 2>&1 || true
  VOUT=$(tofu -chdir="$MODULE" validate 2>&1) && VRC=0 || VRC=$?
  assert_eq "0" "$VRC" "tofu validate succeeds"
  [ "$VRC" -eq 0 ] || echo "$VOUT" >&2
else
  echo "  skip tofu not installed"
fi

finish_tests
