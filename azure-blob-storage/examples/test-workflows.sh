#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/assert.sh"

WF="$SERVICE_PATH/workflows/azure"

echo "== every workflow the handlers can dispatch to exists =="
for w in create update delete read link link-update unlink; do
  assert_eq "present" "$([ -f "$WF/$w.yaml" ] && echo present || echo absent)" "$w.yaml exists"
done

echo "== every workflow is valid YAML =="
for f in "$WF"/*.yaml; do
  assert_eq "ok" "$(python3 -c "import yaml,sys; yaml.safe_load(open('$f')); print('ok')" 2>/dev/null || echo bad)" "valid YAML: $(basename "$f")"
done

echo "== every referenced script exists and is executable =="
MISSING=""
for f in "$WF"/*.yaml; do
  while read -r script; do
    [ -n "$script" ] || continue
    resolved="${script/\$SERVICE_PATH/$SERVICE_PATH}"
    if [ ! -x "$resolved" ]; then
      MISSING="$MISSING $(basename "$f"):$script"
    fi
  done < <(python3 -c "
import yaml,sys
d = yaml.safe_load(open('$f')) or {}
for s in (d.get('steps') or []):
    if s.get('file'):
        print(s['file'])
")
done
assert_eq "" "$MISSING" "all referenced step scripts exist and are executable"

echo "== create and update resolve credentials, build context, apply, write outputs =="
for w in create update; do
  STEPS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml'))
print('|'.join(s['name'] for s in d['steps']))
")
  assert_eq "resolve azure credentials|build context|tofu|write service outputs" "$STEPS" "$w step order"
  ACTION=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml'))
print([s for s in d['steps'] if s['name']=='tofu'][0]['configuration']['TOFU_ACTION'])
")
  assert_eq "apply" "$ACTION" "$w uses TOFU_ACTION=apply"
done

echo "== delete destroys then cleans up the tfstate container =="
DEL_STEPS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/delete.yaml'))
print('|'.join(s['name'] for s in d['steps']))
")
assert_eq "resolve azure credentials|build context|tofu" "$DEL_STEPS" "delete step order"
DEL_ACTION=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/delete.yaml'))
print([s for s in d['steps'] if s['name']=='tofu'][0]['configuration']['TOFU_ACTION'])
")
assert_eq "destroy" "$DEL_ACTION" "delete uses TOFU_ACTION=destroy"

echo "== link builds the permissions context before applying =="
LINK_STEPS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/link.yaml'))
print('|'.join(s['name'] for s in d['steps']))
")
assert_eq "resolve azure credentials|build context|build permissions context|tofu|write link outputs" "$LINK_STEPS" "link step order"

echo "== link-update and unlink reuse link.yaml through include =="
for w in link-update unlink; do
  INC=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml')) or {}
print(','.join(d.get('include') or []))
")
  assert_contains "$INC" "workflows/azure/link.yaml" "$w includes link.yaml"
  REPLACE=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml')) or {}
print(','.join(s.get('action','') for s in (d.get('steps') or [])))
")
  assert_contains "$REPLACE" "replace" "$w replaces a step rather than redefining the workflow"
done

UNLINK_ACTION=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/unlink.yaml'))
print([s for s in d['steps'] if s['name']=='tofu'][0]['configuration']['TOFU_ACTION'])
")
assert_eq "destroy" "$UNLINK_ACTION" "unlink destroys the link's module"

LINKUPD_ACTION=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/link-update.yaml'))
print([s for s in d['steps'] if s['name']=='tofu'][0]['configuration']['TOFU_ACTION'])
")
assert_eq "apply" "$LINKUPD_ACTION" "link-update applies"

echo "== read.yaml must not run tofu: a read may not touch Azure =="
READ_RUNS_TOFU=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/read.yaml'))
print(any('do_tofu' in (s.get('file') or '') for s in d['steps']))
")
assert_eq "False" "$READ_RUNS_TOFU" "read.yaml invokes no tofu step"

echo "== read.yaml has no credential step, which is only honest while it runs no tofu =="
READ_NAMES=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/read.yaml'))
print('|'.join(s['name'] for s in d['steps']))
")
assert_eq "build context|read current state" "$READ_NAMES" "read.yaml step order"

echo "== credential variables are declared as step outputs or they never propagate =="
for w in create update delete link; do
  OUTS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml'))
s = [x for x in d['steps'] if x['name']=='resolve azure credentials'][0]
print(' '.join(o['name'] for o in s.get('output') or []))
")
  for v in ARM_SUBSCRIPTION_ID ARM_CLIENT_ID ARM_TENANT_ID; do
    assert_contains "$OUTS" "$v" "$w declares $v as a step output"
  done
done

echo "== build_context declares the variables do_tofu needs =="
for w in create update delete; do
  OUTS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/$w.yaml'))
s = [x for x in d['steps'] if x['name']=='build context'][0]
print(' '.join(o['name'] for o in s.get('output') or []))
")
  for v in OUTPUT_DIR TOFU_MODULE_DIR TOFU_INIT_VARIABLES TOFU_VARIABLES; do
    assert_contains "$OUTS" "$v" "$w declares $v"
  done
done


echo "== link declares the LINK_* variables build_permissions_context needs =="
LINK_OUTS=$(python3 -c "
import yaml
d = yaml.safe_load(open('$WF/link.yaml'))
s = [x for x in d['steps'] if x['name']=='build context'][0]
print(' '.join(o['name'] for o in s.get('output') or []))
")
for v in LINK_ID LINK_CONTAINER_NAME LINK_ACCESS_LEVEL LINK_SAS_TTL_DAYS TFSTATE_CONTAINER TFSTATE_STORAGE_ACCOUNT TFSTATE_RESOURCE_GROUP; do
  assert_contains "$LINK_OUTS" "$v" "link declares $v"
done

finish_tests
