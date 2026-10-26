assert_eq() { [ "$1" = "$2" ] || { echo "FAIL: $3 (expected '$1', got '$2')"; exit 1; }; echo "ok: $3"; }
assert_fails() { local l=$1; shift; if "$@" >/dev/null 2>&1; then echo "FAIL: $l (command succeeded)"; exit 1; fi; echo "ok: $l"; }
