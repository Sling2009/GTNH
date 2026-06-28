#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

assert() {
  local description="$1" condition="$2"
  if eval "$condition"; then
    echo "  PASS: $description"
    ((PASS++)) || true
  else
    echo "  FAIL: $description"
    ((FAIL++)) || true
  fi
}

# Source merge functions without executing main
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../entrypoint.sh"

echo ""
echo "=== merge_properties ==="

OLD="$TESTDIR/server.properties"
NEW="$TESTDIR/server.properties.new"

cat > "$OLD" << 'EOF'
# My server config
existing_key=my_custom_value
server-port=25565
EOF

cat > "$NEW" << 'EOF'
# Default config
existing_key=default_value
server-port=25565
new_key=new_default
another_new=42
EOF

merge_properties "$OLD" "$NEW"

assert "existing value is preserved"    "grep -q 'existing_key=my_custom_value' '$OLD'"
assert "new_key is added"               "grep -q 'new_key=new_default' '$OLD'"
assert "another_new is added"           "grep -q 'another_new=42' '$OLD'"
assert "backup file created"            "[ -f '${OLD}.bak' ]"
assert "default value not overwritten"  "! grep -q 'existing_key=default_value' '$OLD'"

echo ""
echo "=== merge_json ==="

if ! command -v jq &>/dev/null; then
  echo "  SKIP: jq not found – JSON tests skipped (available in CI and Docker image)"
else
  OLD="$TESTDIR/config.json"
  NEW="$TESTDIR/config.json.new"

  printf '{"existing": "my_value", "nested": {"a": 1}}\n' > "$OLD"
  printf '{"existing": "default", "nested": {"a": 99, "b": 2}, "new_key": true}\n' > "$NEW"

  merge_json "$OLD" "$NEW"

  assert "existing string is preserved"   "jq -e '.existing == \"my_value\"' '$OLD' > /dev/null"
  assert "nested.a is preserved"          "jq -e '.nested.a == 1' '$OLD' > /dev/null"
  assert "nested.b is added"             "jq -e '.nested.b == 2' '$OLD' > /dev/null"
  assert "new_key is added"               "jq -e '.new_key == true' '$OLD' > /dev/null"
fi

echo ""
echo "=== merge_cfg ==="

OLD="$TESTDIR/mod.cfg"
NEW="$TESTDIR/mod.cfg.new"

cat > "$OLD" << 'EOF'
# Config file
general {
    B:existingSetting=false
    I:existingInt=10
}
EOF

cat > "$NEW" << 'EOF'
# Config file
general {
    B:existingSetting=true
    I:existingInt=99
    S:newSetting=hello
    S:emptyValue=
}
EOF

merge_cfg "$OLD" "$NEW"

assert "existingSetting is preserved"   "grep -q 'B:existingSetting=false' '$OLD'"
assert "existingInt is preserved"       "grep -q 'I:existingInt=10' '$OLD'"
assert "newSetting is added"            "grep -q 'S:newSetting=hello' '$OLD'"
assert "emptyValue is added"            "grep -q 'S:emptyValue=' '$OLD'"
assert "backup file created"            "[ -f '${OLD}.bak' ]"

echo ""
echo "=== merge_config dispatch ==="

# JSON dispatch (only if jq available)
if command -v jq &>/dev/null; then
  OLD="$TESTDIR/dispatch.json"
  NEW="$TESTDIR/dispatch.json.new"
  printf '{"a": 1}\n' > "$OLD"
  printf '{"a": 99, "b": 2}\n' > "$NEW"
  merge_config "$OLD" "$NEW"
  assert "dispatch: json old value kept"  "jq -e '.a == 1' '$OLD' > /dev/null"
  assert "dispatch: json new key added"   "jq -e '.b == 2' '$OLD' > /dev/null"
fi

# New file (doesn't exist yet) — should be copied
NEW="$TESTDIR/new_file.json"
OLD="$TESTDIR/nonexistent.json"
printf '{"brand_new": true}\n' > "$NEW"
merge_config "$OLD" "$NEW"
assert "dispatch: new file is copied"   "[ -f '$OLD' ]"

echo ""
echo "================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "================================="
[ "$FAIL" -eq 0 ]
