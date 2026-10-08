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

python3 - "$HOME/.secretforge/config.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    config = json.load(f)
record = config["secrets"]["API_KEY"]
assert record["format_version"] == 2
assert len(record["mac"]) == 64
PY

cp "$HOME/.secretforge/config.json" "$TEST_HOME/integrity-backup"
python3 - "$HOME/.secretforge/config.json" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    config = json.load(f)
record = config["secrets"]["API_KEY"]
prefix = "secretforge:v2:"
index = len(prefix)
record["value"] = record["value"][:index] + ("A" if record["value"][index] != "A" else "B") + record["value"][index + 1:]
with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f)
PY
cp "$HOME/.secretforge/config.json" "$TEST_HOME/tampered-backup"
if "$CLI" get API_KEY >"$TEST_HOME/tampered-output" 2>"$TEST_HOME/tampered-error"; then
  fail "tampered secret must be rejected"
fi
grep -q 'integrity check failed' "$TEST_HOME/tampered-error" || fail "tamper rejection message"
[[ ! -s "$TEST_HOME/tampered-output" ]] || fail "tampered secret was returned"
if "$CLI" migrate >"$TEST_HOME/migrate-output" 2>"$TEST_HOME/migrate-error"; then
  fail "migration must reject an invalid authenticated record"
fi
grep -q 'no migration was applied' "$TEST_HOME/migrate-error" || fail "migration rejection message"
cmp -s "$HOME/.secretforge/config.json" "$TEST_HOME/tampered-backup" || fail "migration changed tampered vault"
cp "$TEST_HOME/integrity-backup" "$HOME/.secretforge/config.json"

python3 - "$HOME/.secretforge/config.json" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    config = json.load(f)
config["secrets"]["API_KEY"]["format_version"] = 1
with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f)
PY
if "$CLI" get API_KEY >"$TEST_HOME/downgrade-output" 2>"$TEST_HOME/downgrade-error"; then
  fail "downgraded authenticated secret must be rejected"
fi
grep -q 'integrity check failed' "$TEST_HOME/downgrade-error" || fail "downgrade rejection message"
[[ ! -s "$TEST_HOME/downgrade-output" ]] || fail "downgraded secret was returned"
cp "$TEST_HOME/integrity-backup" "$HOME/.secretforge/config.json"

python3 - "$HOME/.secretforge/config.json" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    config = json.load(f)
record = config["secrets"]["API_KEY"]
record.pop("format_version")
record.pop("mac")
prefix = "secretforge:v2:"
if record["value"].startswith(prefix):
    record["value"] = record["value"][len(prefix):]
with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f)
PY
[[ "$("$CLI" get API_KEY 2>"$TEST_HOME/legacy-warning")" == "$value" ]] || fail "legacy secret compatibility"
grep -q 'legacy secret has no integrity check' "$TEST_HOME/legacy-warning" || fail "legacy warning"
[[ "$("$CLI" migrate)" == 'Migrated 1 legacy secret(s).' ]] || fail "legacy migration"
[[ "$("$CLI" get API_KEY)" == "$value" ]] || fail "migrated legacy secret"
python3 - "$HOME/.secretforge/config.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    config = json.load(f)
record = config["secrets"]["API_KEY"]
assert record["format_version"] == 2
assert len(record["mac"]) == 64
PY
[[ "$("$CLI" migrate)" == 'Migrated 0 legacy secret(s).' ]] || fail "idempotent migration"

printf '%s\n' 'piped-value' | "$CLI" set PIPED_KEY >/dev/null
[[ "$("$CLI" get PIPED_KEY)" == 'piped-value' ]] || fail "piped secret input"

python3 - "$CLI" <<'PY'
import os, pty, select, subprocess, sys, time

cli = sys.argv[1]
master, slave = pty.openpty()
process = subprocess.Popen(
    [cli, "set", "PROMPTED_KEY"],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    env=os.environ.copy(),
    close_fds=True,
)
os.close(slave)
transcript = bytearray()
sent = False
deadline = time.monotonic() + 10

while time.monotonic() < deadline:
    ready, _, _ = select.select([master], [], [], 0.1)
    if ready:
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        transcript.extend(chunk)
        if not sent and b"Secret value: " in transcript:
            os.write(master, b"hidden-terminal-value\n")
            sent = True
    if process.poll() is not None:
        break

os.close(master)
if process.poll() is None:
    process.kill()
    process.wait()
    raise SystemExit("FAIL: hidden-input prompt timed out")
if process.returncode != 0:
    raise SystemExit("FAIL: hidden-input command failed: " + transcript.decode(errors="replace"))
if not sent or b"hidden-terminal-value" in transcript:
    raise SystemExit("FAIL: terminal secret was missing or echoed")
PY
[[ "$("$CLI" get PROMPTED_KEY)" == 'hidden-terminal-value' ]] || fail "hidden terminal input"

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
