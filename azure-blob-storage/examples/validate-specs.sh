#!/bin/bash
# Validates the service and link specs against the nullplatform skills checklist.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

SERVICE_SPEC="$SERVICE_PATH/specs/service-spec.json.tpl"
LINK_SPEC="$SERVICE_PATH/specs/links/connect.json.tpl"

echo "== spec files exist and are valid JSON =="
for f in "$SERVICE_SPEC" "$LINK_SPEC"; do
  if [ -f "$f" ]; then
    assert_eq "ok" "$(jq -e . "$f" >/dev/null 2>&1 && echo ok || echo bad)" "valid JSON: $(basename "$f")"
  else
    assert_eq "present" "missing" "file exists: $f"
  fi
done

echo "== schema lives in attributes.schema =="
assert_eq "object" "$(jq -r '.attributes.schema.type // "MISSING"' "$SERVICE_SPEC" 2>/dev/null)" "service schema type"
assert_eq "object" "$(jq -r '.attributes.schema.type // "MISSING"' "$LINK_SPEC" 2>/dev/null)" "link schema type"

echo "== specification_schema is absent =="
assert_eq "absent" "$(jq -e 'has("specification_schema")' "$SERVICE_SPEC" >/dev/null 2>&1 && echo present || echo absent)" "service has no specification_schema"
assert_eq "absent" "$(jq -e 'has("specification_schema")' "$LINK_SPEC" >/dev/null 2>&1 && echo present || echo absent)" "link has no specification_schema"

echo "== identity and selectors =="
assert_eq "azure-blob-storage" "$(jq -r '.slug' "$SERVICE_SPEC" 2>/dev/null)" "service slug"
assert_eq "dependency" "$(jq -r '.type' "$SERVICE_SPEC" 2>/dev/null)" "service type"
assert_eq "Azure" "$(jq -r '.selectors.provider' "$SERVICE_SPEC" 2>/dev/null)" "service provider selector"
assert_eq "Storage" "$(jq -r '.selectors.category' "$SERVICE_SPEC" 2>/dev/null)" "service category selector"
assert_eq "connect" "$(jq -r '.available_links[0]' "$SERVICE_SPEC" 2>/dev/null)" "service declares the connect link"
assert_eq "connect" "$(jq -r '.slug' "$LINK_SPEC" 2>/dev/null)" "link slug"

echo "== required service attributes exist =="
for a in account_tier replication_type access_tier blob_versioning soft_delete_days \
         container_soft_delete_days account_name primary_blob_endpoint account_id resource_group_name; do
  assert_eq "present" "$(jq -e --arg a "$a" '.attributes.schema.properties[$a]' "$SERVICE_SPEC" >/dev/null 2>&1 && echo present || echo missing)" "service attribute $a"
done

echo "== the service required array is exactly the two inputs with no safe default =="
assert_eq "account_tier,replication_type" "$(jq -r '.attributes.schema.required | join(",")' "$SERVICE_SPEC" 2>/dev/null)" "service required array"

echo "== output attributes are not editable =="
for a in account_name primary_blob_endpoint account_id resource_group_name; do
  assert_eq "0" "$(jq -r --arg a "$a" '.attributes.schema.properties[$a].editableOn | length' "$SERVICE_SPEC" 2>/dev/null)" "$a editableOn is empty"
done

echo "== exported service attributes =="
assert_eq "true" "$(jq -r '.attributes.schema.properties.account_name.export' "$SERVICE_SPEC" 2>/dev/null)" "account_name exported"
assert_eq "true" "$(jq -r '.attributes.schema.properties.primary_blob_endpoint.export' "$SERVICE_SPEC" 2>/dev/null)" "primary_blob_endpoint exported"
assert_eq "false" "$(jq -r '.attributes.schema.properties.account_id.export' "$SERVICE_SPEC" 2>/dev/null)" "account_id not exported"
assert_eq "false" "$(jq -r '.attributes.schema.properties.resource_group_name.export' "$SERVICE_SPEC" 2>/dev/null)" "resource_group_name not exported"

echo "== TLS and HTTPS are not user-editable =="
assert_eq "null" "$(jq -r '.attributes.schema.properties.min_tls_version' "$SERVICE_SPEC" 2>/dev/null)" "min_tls_version absent from schema"
assert_eq "null" "$(jq -r '.attributes.schema.properties.https_only' "$SERVICE_SPEC" 2>/dev/null)" "https_only absent from schema"

echo "== link attributes =="
for a in container_name accessLevel sas_ttl_days sas_token; do
  assert_eq "present" "$(jq -e --arg a "$a" '.attributes.schema.properties[$a]' "$LINK_SPEC" >/dev/null 2>&1 && echo present || echo missing)" "link attribute $a"
done
assert_eq "read-write" "$(jq -r '.attributes.schema.properties.accessLevel.default' "$LINK_SPEC" 2>/dev/null)" "accessLevel default"
assert_eq "read,write,read-write" "$(jq -r '.attributes.schema.properties.accessLevel.enum | join(",")' "$LINK_SPEC" 2>/dev/null)" "accessLevel enum"
assert_eq "true" "$(jq -r '.attributes.schema.properties.sas_token.export.secret' "$LINK_SPEC" 2>/dev/null)" "sas_token exported as secret"
assert_eq "container_name" "$(jq -r '.attributes.schema.required | join(",")' "$LINK_SPEC" 2>/dev/null)" "container_name is required"

echo "== the link must not re-export service attributes =="
# Both spellings are checked: primary_blob_endpoint is the name the service spec
# actually uses, so it is the one that could really collide. blob_endpoint is kept
# because permissions/ emits a tofu output by that name, which is the plausible slip.
assert_eq "null" "$(jq -r '.attributes.schema.properties.account_name' "$LINK_SPEC" 2>/dev/null)" "link does not redeclare account_name"
assert_eq "null" "$(jq -r '.attributes.schema.properties.primary_blob_endpoint' "$LINK_SPEC" 2>/dev/null)" "link does not redeclare primary_blob_endpoint"
assert_eq "null" "$(jq -r '.attributes.schema.properties.blob_endpoint' "$LINK_SPEC" 2>/dev/null)" "link does not declare blob_endpoint either"

finish_tests
