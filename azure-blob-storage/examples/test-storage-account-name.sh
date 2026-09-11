#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

SAN="$SERVICE_PATH/scripts/azure/storage_account_name"
SID="9f8e7d6c-1234-4321-abcd-000000000000"

echo "== happy path =="
assert_eq "myblobstore9f8e7d6c" "$("$SAN" "My Blob Store" "$SID")" "spaces and case stripped, id suffix appended"

echo "== hyphens are removed (Azure forbids them) =="
assert_eq "orderspayments9f8e7d6c" "$("$SAN" "orders-payments" "$SID")" "hyphens dropped"

echo "== length cap is 24 and the id suffix survives =="
LONG=$("$SAN" "averyveryverylongservicenamethatoverflows" "$SID")
assert_eq "24" "${#LONG}" "result is exactly 24 chars"
assert_eq "9f8e7d6c" "${LONG: -8}" "id suffix preserved at the end"
assert_eq "averyveryverylon9f8e7d6c" "$LONG" "base truncated to 16 chars so the 8-char suffix fits"

echo "== empty and unusable names fall back =="
assert_eq "npblob9f8e7d6c" "$("$SAN" "" "$SID")" "empty name falls back to npblob"
assert_eq "npblob9f8e7d6c" "$("$SAN" "!!!___###" "$SID")" "name that sanitizes to nothing falls back"

echo "== output always satisfies the Azure pattern =="
for name in "" "a" "ab" "My Blob Store" "!!!" "averyveryverylongservicenamethatoverflows" "UPPER-CASE-99"; do
  out=$("$SAN" "$name" "$SID")
  if [[ "$out" =~ ^[a-z0-9]{3,24}$ ]]; then
    echo "  ok   valid for input [$name] -> $out"
  else
    echo "  FAIL invalid for input [$name] -> $out" >&2
    FAILURES=$((FAILURES + 1))
  fi
done

echo "== missing service_id is an error =="
assert_fails "no service_id exits non-zero" "$SAN" "some-name"

finish_tests
