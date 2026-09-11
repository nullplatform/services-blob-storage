#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SECRET="sv=2024-11-04&sr=c&sig=SUPERSECRETSIGNATURE&sp=rl"

run_write_link_outputs() {
  (
    export PATH="$SCRIPT_DIR/stub-bin:$PATH"
    export NP_STUB_LOG="$TMP/np.log" TOFU_STUB_LOG="$TMP/tofu.log"
    export OUTPUT_DIR="$TMP/out"; mkdir -p "$OUTPUT_DIR"
    export CONTEXT='{"link":{"id":"lnk-77","slug":"blob-main"}}'
    export TOFU_STUB_OUTPUT_container_name="${1-}"
    export TOFU_STUB_OUTPUT_sas_token="${2-}"
    bash "$SERVICE_PATH/scripts/azure/write_link_outputs" 2>&1
  )
}

echo "== happy path =="
: > "$TMP/np.log"
OUT=$(run_write_link_outputs "media-uploads" "$SECRET")
NP_CALL=$(grep 'link patch' "$TMP/np.log" | head -1)
assert_contains "$NP_CALL" "--id lnk-77" "patches the right link"
BODY=$(printf '%s' "$NP_CALL" | sed 's/.*--body //')
assert_eq "media-uploads" "$(printf '%s' "$BODY" | jq -r '.attributes.container_name')" "container_name patched"
assert_eq "$SECRET" "$(printf '%s' "$BODY" | jq -r '.attributes.sas_token')" "sas_token patched"

echo "== only the two link-owned attributes are patched =="
assert_eq "container_name sas_token" "$(printf '%s' "$BODY" | jq -r '.attributes | keys | join(" ")')" "no service attributes duplicated onto the link"

echo "== the SAS is never printed to the log =="
if printf '%s' "$OUT" | grep -q "SUPERSECRETSIGNATURE"; then
  echo "  FAIL the SAS signature was written to stdout" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   the SAS signature is not printed"
fi
assert_contains "$OUT" "****" "the SAS is masked in the log"

echo "== no container_name means no patch =="
: > "$TMP/np.log"
OUT=$(run_write_link_outputs "" "")
assert_contains "$OUT" "Skipping" "warns and skips"
if grep -q 'link patch' "$TMP/np.log"; then
  echo "  FAIL patched with no outputs available" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch when tofu produced no outputs"
fi

echo "== container_name present but sas_token empty: patch what is present (C2) =="
: > "$TMP/np.log"
OUT=$(run_write_link_outputs "media-uploads" "")
NP_CALL=$(grep 'link patch' "$TMP/np.log" | head -1)
assert_contains "$NP_CALL" "--id lnk-77" "still patches the link"
BODY=$(printf '%s' "$NP_CALL" | sed 's/.*--body //')
assert_eq "container_name" "$(printf '%s' "$BODY" | jq -r '.attributes | keys | join(" ")')" \
  "empty sas_token is omitted, not sent as an empty string"
assert_contains "$OUT" "sas_token" "log mentions the empty sas_token"

echo "== NP_SKIP_TOFU=true no-ops without touching OUTPUT_DIR or tofu (C1) =="
: > "$TMP/np.log"
: > "$TMP/tofu.log"
SKIP_OUT=$(
  export PATH="$SCRIPT_DIR/stub-bin:$PATH"
  export NP_STUB_LOG="$TMP/np.log" TOFU_STUB_LOG="$TMP/tofu.log"
  export CONTEXT='{"link":{"id":"lnk-77","slug":"blob-main"}}'
  export NP_SKIP_TOFU=true
  # A deliberately bogus OUTPUT_DIR: if the guard did not return before "cd",
  # this would fail with "No such file or directory" instead of a clean skip.
  export OUTPUT_DIR="$TMP/does-not-exist"
  bash "$SERVICE_PATH/scripts/azure/write_link_outputs" 2>&1
) && SKIP_RC=0 || SKIP_RC=$?
assert_eq "0" "$SKIP_RC" "exits 0 when NP_SKIP_TOFU=true"
assert_eq "0" "$(wc -l < "$TMP/tofu.log" | tr -d '[:space:]')" "tofu was never invoked"
if grep -q 'link patch' "$TMP/np.log"; then
  echo "  FAIL patched the link despite NP_SKIP_TOFU=true" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch the link"
fi

echo "== tofu missing from PATH fails loudly instead of silently skipping (C2) =="
NO_TOFU_BIN="$TMP/no-tofu-bin"
mkdir -p "$NO_TOFU_BIN"
cp "$SCRIPT_DIR/stub-bin/np" "$NO_TOFU_BIN/np"
: > "$TMP/np.log"
NOTOFU_OUT=$(
  export PATH="$NO_TOFU_BIN:/usr/bin:/bin"
  export NP_STUB_LOG="$TMP/np.log"
  export OUTPUT_DIR="$TMP/out-notofu"; mkdir -p "$OUTPUT_DIR"
  export CONTEXT='{"link":{"id":"lnk-77","slug":"blob-main"}}'
  bash "$SERVICE_PATH/scripts/azure/write_link_outputs" 2>&1
) && NOTOFU_RC=0 || NOTOFU_RC=$?
assert_eq "1" "$NOTOFU_RC" "exits non-zero when tofu is not on PATH"
assert_contains "$NOTOFU_OUT" "not on PATH" "names the cause instead of warning-and-skipping"
if grep -q 'link patch' "$TMP/np.log"; then
  echo "  FAIL patched the link despite tofu being unavailable" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "  ok   did not patch when tofu was unavailable"
fi

finish_tests
