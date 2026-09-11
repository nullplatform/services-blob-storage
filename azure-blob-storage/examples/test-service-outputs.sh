#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CONTEXT_JSON='{"service":{"id":"svc-42"}}'

run_write_outputs() {
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH"
    export NP_STUB_LOG="$TMP/np.log"
    export TOFU_STUB_LOG="$TMP/tofu.log"
    export OUTPUT_DIR="$TMP/out"; mkdir -p "$OUTPUT_DIR"
    export CONTEXT="$CONTEXT_JSON"
    export TOFU_STUB_OUTPUT_account_name="${1-}"
    export TOFU_STUB_OUTPUT_primary_blob_endpoint="${2-}"
    export TOFU_STUB_OUTPUT_account_id="${3-}"
    export TOFU_STUB_OUTPUT_resource_group_name="${4-}"
    bash "$SERVICE_PATH/scripts/azure/write_service_outputs" 2>&1
  )
}

echo "== happy path patches every attribute =="
: > "$TMP/np.log"
OUT=$(run_write_outputs "mediaassets9f8e" "https://mediaassets9f8e.blob.core.windows.net/" "/subscriptions/s/rg/x" "rg-blob-test")
NP_CALL=$(grep 'service patch' "$TMP/np.log" | head -1)
assert_contains "$NP_CALL" "--id svc-42" "patches the right service"
BODY=$(printf '%s' "$NP_CALL" | sed 's/.*--body //')
assert_eq "mediaassets9f8e" "$(printf '%s' "$BODY" | jq -r '.attributes.account_name')" "account_name patched"
assert_eq "https://mediaassets9f8e.blob.core.windows.net/" "$(printf '%s' "$BODY" | jq -r '.attributes.primary_blob_endpoint')" "primary_blob_endpoint patched"
assert_eq "/subscriptions/s/rg/x" "$(printf '%s' "$BODY" | jq -r '.attributes.account_id')" "account_id patched"
assert_eq "rg-blob-test" "$(printf '%s' "$BODY" | jq -r '.attributes.resource_group_name')" "resource_group_name patched"

echo "== no account_name means no patch at all =="
: > "$TMP/np.log"
OUT=$(run_write_outputs "" "" "" "")
assert_contains "$OUT" "Skipping" "warns and skips"
if grep -q 'service patch' "$TMP/np.log"; then
  echo "  FAIL patched with no outputs available" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch when tofu produced no outputs"
fi

echo "== partial outputs: present values are patched, empty ones are not overwritten (C2) =="
: > "$TMP/np.log"
OUT=$(run_write_outputs "mediaassets9f8e" "" "" "rg-blob-test")
NP_CALL=$(grep 'service patch' "$TMP/np.log" | head -1)
assert_contains "$NP_CALL" "--id svc-42" "still patches the service"
BODY=$(printf '%s' "$NP_CALL" | sed 's/.*--body //')
assert_eq "mediaassets9f8e" "$(printf '%s' "$BODY" | jq -r '.attributes.account_name')" "account_name patched"
assert_eq "rg-blob-test" "$(printf '%s' "$BODY" | jq -r '.attributes.resource_group_name')" "resource_group_name patched (was present)"
assert_eq "account_name resource_group_name" "$(printf '%s' "$BODY" | jq -r '.attributes | keys | join(" ")')" \
  "empty outputs (primary_blob_endpoint, account_id) are omitted, not sent as empty strings"
assert_contains "$OUT" "primary_blob_endpoint" "log names which outputs were empty"
assert_contains "$OUT" "account_id" "log names which outputs were empty"

echo "== tofu missing from PATH fails loudly instead of silently skipping (C2) =="
NO_TOFU_BIN="$TMP/no-tofu-bin"
mkdir -p "$NO_TOFU_BIN"
cp "$SCRIPT_DIR/stub-bin/np" "$NO_TOFU_BIN/np"
: > "$TMP/np.log"
NOTOFU_OUT=$(
  # Deliberately exclude stub-bin (which has its own tofu) and the rest of
  # the ambient PATH (which has the real tofu binary this dev machine uses).
  export PATH="$NO_TOFU_BIN:/usr/bin:/bin"
  export NP_STUB_LOG="$TMP/np.log"
  export OUTPUT_DIR="$TMP/out-notofu"; mkdir -p "$OUTPUT_DIR"
  export CONTEXT="$CONTEXT_JSON"
  bash "$SERVICE_PATH/scripts/azure/write_service_outputs" 2>&1
) && NOTOFU_RC=0 || NOTOFU_RC=$?
assert_eq "1" "$NOTOFU_RC" "exits non-zero when tofu is not on PATH"
assert_contains "$NOTOFU_OUT" "not on PATH" "names the cause instead of warning-and-skipping"
if grep -q 'service patch' "$TMP/np.log"; then
  echo "  FAIL patched the service despite tofu being unavailable" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch when tofu was unavailable"
fi

echo "== 'tofu output -json' failing outright also fails loudly (C2) =="
: > "$TMP/np.log"
FAILOUT=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH"
  export NP_STUB_LOG="$TMP/np.log" TOFU_STUB_LOG="$TMP/tofu.log"
  export TOFU_STUB_FAIL_OUTPUT=true
  export OUTPUT_DIR="$TMP/out-failout"; mkdir -p "$OUTPUT_DIR"
  export CONTEXT="$CONTEXT_JSON"
  bash "$SERVICE_PATH/scripts/azure/write_service_outputs" 2>&1
) && FAILOUT_RC=0 || FAILOUT_RC=$?
assert_eq "1" "$FAILOUT_RC" "exits non-zero when 'tofu output -json' itself fails"
assert_contains "$FAILOUT" "tofu output -json" "names the failing command"
if grep -q 'service patch' "$TMP/np.log"; then
  echo "  FAIL patched the service despite 'tofu output -json' failing" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch when 'tofu output -json' failed"
fi

echo "== no secret is ever patched =="
: > "$TMP/np.log"
run_write_outputs "acct" "https://acct.blob.core.windows.net/" "/id" "rg" >/dev/null
LOG=$(cat "$TMP/np.log")
for forbidden in primary_access_key primary_connection_string sas_token; do
  if printf '%s' "$LOG" | grep -q "$forbidden"; then
    echo "  FAIL $forbidden appeared in a service patch" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "  ok   $forbidden never patched"
  fi
done

finish_tests
