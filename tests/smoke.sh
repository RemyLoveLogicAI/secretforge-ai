#!/usr/bin/env bash
set -euo pipefail

CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$CLI_DIR/secretforge"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
export PATH="$CLI_DIR:$PATH"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ "$("$CLI" --version)" == "SecretForge CLI v1.2.0" ]] || fail "version output"
"$CLI" init >/dev/null
if "$CLI" get absent >/dev/null 2>&1; then
  fail "missing secret should fail"
fi

value="value with spaces, \$dollars, and \"quotes\""
"$CLI" set API_KEY "$value" >/dev/null
[[ "$("$CLI" get API_KEY)" == "$value" ]] || fail "round-trip secret"

eval "$("$CLI" export)"
[[ "$API_KEY" == "$value" ]] || fail "exported environment value"

python3 - "$HOME/.secretforge" <<'PY'
import os, stat, sys

vault = sys.argv[1]
assert stat.S_IMODE(os.stat(vault).st_mode) == 0o700
for name in (".key", "config.json"):
    assert stat.S_IMODE(os.stat(os.path.join(vault, name)).st_mode) == 0o600
PY

marker="$TEST_HOME/should-not-execute"
malicious_key="x\"] ; __import__(\"os\").system(\"touch $marker\"); data.setdefault(\"secrets\", {})[\"y"
"$CLI" set "$malicious_key" test-value >/dev/null
[[ "$("$CLI" get "$malicious_key")" == "test-value" ]] || fail "quoted secret key"
[[ ! -e "$marker" ]] || fail "secret key executed as code"
"$CLI" export >/dev/null 2>&1 && fail "invalid environment key should fail export"

if "$CLI" set ONLY_KEY >/dev/null 2>&1; then
  fail "missing set value should fail"
fi

cp "$HOME/.secretforge/config.json" "$TEST_HOME/config.backup"
rm "$HOME/.secretforge/.key"
if "$CLI" init >/dev/null 2>&1; then
  fail "incomplete vault should not be reinitialized"
fi
cmp -s "$TEST_HOME/config.backup" "$HOME/.secretforge/config.json" || fail "incomplete vault config was modified"
[[ ! -e "$HOME/.secretforge/.key" ]] || fail "incomplete vault key was replaced"

echo "SecretForge smoke tests passed."
