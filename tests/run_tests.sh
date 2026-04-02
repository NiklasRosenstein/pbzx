#!/usr/bin/env bash
#
# Integration tests for the pbzx binary.
# Expects: ./pbzx built, and tests/fixtures/ populated by gen_fixtures.py.
#
set -euo pipefail

PBZX="./pbzx"
FIXTURES="tests/fixtures"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT
PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1 -- $2"; SKIP=$((SKIP + 1)); }

# ========== A. CLI Parsing ==========

echo "--- CLI Parsing ---"

# A1: No arguments
if stderr=$("$PBZX" 2>&1); then
    fail "A1: no args" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "missing filename argument"; then
        pass "A1: no args -> missing filename"
    else
        fail "A1: no args" "stderr: $stderr"
    fi
fi

# A2: -h flag
if stderr=$("$PBZX" -h 2>&1); then
    if echo "$stderr" | grep -q "usage"; then
        pass "A2: -h shows usage"
    else
        fail "A2: -h" "stderr missing 'usage': $stderr"
    fi
else
    fail "A2: -h" "expected exit 0"
fi

# A3: -v flag
if stdout=$("$PBZX" -v 2>&1); then
    if echo "$stdout" | grep -q "pbzx v1.0.2"; then
        pass "A3: -v shows version"
    else
        fail "A3: -v" "output: $stdout"
    fi
else
    fail "A3: -v" "expected exit 0"
fi

# A4: -n without filename
if stderr=$("$PBZX" -n 2>&1); then
    fail "A4: -n no file" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "missing filename argument"; then
        pass "A4: -n no file -> missing filename"
    else
        fail "A4: -n no file" "stderr: $stderr"
    fi
fi

# A5: Unknown flag
if stderr=$("$PBZX" -x 2>&1); then
    fail "A5: unknown flag" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "unrecognized flag"; then
        pass "A5: unknown flag -> unrecognized"
    else
        fail "A5: unknown flag" "stderr: $stderr"
    fi
fi

# A6: Too many positional args
if stderr=$("$PBZX" file1.pkg file2.pkg 2>&1); then
    fail "A6: too many args" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "unhandled positional argument"; then
        pass "A6: too many args"
    else
        fail "A6: too many args" "stderr: $stderr"
    fi
fi

# A7: stdin flag with extra positional
if stderr=$("$PBZX" - extra 2>&1); then
    fail "A7: stdin + extra arg" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "unhandled positional argument"; then
        pass "A7: stdin + extra arg"
    else
        fail "A7: stdin + extra arg" "stderr: $stderr"
    fi
fi

# ========== D. PBZX Stream Parsing ==========

echo "--- PBZX Stream Parsing ---"

# D1: Valid single LZMA chunk (raw file mode)
if stdout=$("$PBZX" -n "$FIXTURES/valid_single_lzma.pbzx" 2>/dev/null); then
    expected=$(cat "$FIXTURES/valid_single_lzma.expected")
    if [ "$stdout" = "$expected" ]; then
        pass "D1: valid single LZMA chunk"
    else
        fail "D1: valid single LZMA" "output mismatch"
    fi
else
    fail "D1: valid single LZMA" "non-zero exit"
fi

# D2: Valid plain chunk (16 MiB)
# Compare using checksums to avoid shell variable size limits
if "$PBZX" -n "$FIXTURES/valid_plain.pbzx" 2>/dev/null | shasum -a 256 > "$TMPDIR_TEST/got.sha"; then
    expected_sha=$(shasum -a 256 "$FIXTURES/valid_plain.expected" | awk '{print $1}')
    got_sha=$(awk '{print $1}' "$TMPDIR_TEST/got.sha")
    if [ "$got_sha" = "$expected_sha" ]; then
        pass "D2: valid plain chunk"
    else
        fail "D2: valid plain chunk" "sha256 mismatch: got=$got_sha expected=$expected_sha"
    fi
else
    fail "D2: valid plain chunk" "non-zero exit"
fi

# D3: Valid multi-chunk LZMA
if stdout=$("$PBZX" -n "$FIXTURES/valid_multi_lzma.pbzx" 2>/dev/null); then
    expected=$(cat "$FIXTURES/valid_multi_lzma.expected")
    if [ "$stdout" = "$expected" ]; then
        pass "D3: valid multi-chunk LZMA"
    else
        fail "D3: valid multi-chunk LZMA" "output mismatch"
    fi
else
    fail "D3: valid multi-chunk LZMA" "non-zero exit"
fi

# D4: Invalid magic
if stderr=$("$PBZX" -n "$FIXTURES/bad_magic.pbzx" 2>&1); then
    fail "D4: invalid magic" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "not a pbzx stream"; then
        pass "D4: invalid magic -> rejected"
    else
        fail "D4: invalid magic" "stderr: $stderr"
    fi
fi

# D5: Bad LZMA header
if stderr=$("$PBZX" -n "$FIXTURES/bad_lzma_header.pbzx" 2>&1); then
    fail "D5: bad LZMA header" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "Header is not"; then
        pass "D5: bad LZMA header -> rejected"
    else
        fail "D5: bad LZMA header" "stderr: $stderr"
    fi
fi

# D6: Bad LZMA footer
# Note: The LZMA decoder's own CRC checks catch footer corruption before
# the code's manual "YZ" footer check runs. So this produces an LZMA error
# rather than the "Footer is not YZ" message.
if stderr=$("$PBZX" -n "$FIXTURES/bad_lzma_footer.pbzx" 2>&1); then
    fail "D6: bad LZMA footer" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "LZMA"; then
        pass "D6: bad LZMA footer -> LZMA error"
    else
        fail "D6: bad LZMA footer" "stderr: $stderr"
    fi
fi

# D7: Empty payload (no chunks)
if stdout=$("$PBZX" -n "$FIXTURES/empty_payload.pbzx" 2>/dev/null); then
    if [ -z "$stdout" ]; then
        pass "D7: empty payload -> no output"
    else
        fail "D7: empty payload" "unexpected output: $stdout"
    fi
else
    fail "D7: empty payload" "non-zero exit"
fi

# D8: Stream via stdin
if stdout=$(cat "$FIXTURES/valid_single_lzma.pbzx" | "$PBZX" - 2>/dev/null); then
    expected=$(cat "$FIXTURES/valid_single_lzma.expected")
    if [ "$stdout" = "$expected" ]; then
        pass "D8: stdin mode"
    else
        fail "D8: stdin mode" "output mismatch"
    fi
else
    fail "D8: stdin mode" "non-zero exit"
fi

# D9: Raw file via -n flag (same as D1 but explicit)
if stdout=$("$PBZX" -n "$FIXTURES/valid_single_lzma.pbzx" 2>/dev/null); then
    expected=$(cat "$FIXTURES/valid_single_lzma.expected")
    if [ "$stdout" = "$expected" ]; then
        pass "D9: -n raw file mode"
    else
        fail "D9: -n raw file mode" "output mismatch"
    fi
else
    fail "D9: -n raw file mode" "non-zero exit"
fi

# D10: Large chunk (>4KB, multiple read iterations)
if "$PBZX" -n "$FIXTURES/large_chunk.pbzx" 2>/dev/null | shasum -a 256 > "$TMPDIR_TEST/got.sha"; then
    expected_sha=$(shasum -a 256 "$FIXTURES/large_chunk.expected" | awk '{print $1}')
    got_sha=$(awk '{print $1}' "$TMPDIR_TEST/got.sha")
    if [ "$got_sha" = "$expected_sha" ]; then
        pass "D10: large chunk (multi-read)"
    else
        fail "D10: large chunk" "sha256 mismatch: got=$got_sha expected=$expected_sha"
    fi
else
    fail "D10: large chunk" "non-zero exit"
fi

# D11: Stream via stdin with -n flag (noxar + stdin combined)
if stdout=$(cat "$FIXTURES/valid_single_lzma.pbzx" | "$PBZX" -n - 2>/dev/null); then
    expected=$(cat "$FIXTURES/valid_single_lzma.expected")
    if [ "$stdout" = "$expected" ]; then
        pass "D11: stdin with -n flag"
    else
        fail "D11: stdin with -n flag" "output mismatch"
    fi
else
    fail "D11: stdin with -n flag" "non-zero exit"
fi

# ========== E. Error Handling ==========

echo "--- Error Handling ---"

# E1: Nonexistent file
if stderr=$("$PBZX" -n /tmp/pbzx_no_such_file_12345 2>&1); then
    fail "E1: nonexistent file" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "failed to open"; then
        pass "E1: nonexistent file -> failed to open"
    else
        fail "E1: nonexistent file" "stderr: $stderr"
    fi
fi

# E2: Corrupt LZMA body
if stderr=$("$PBZX" -n "$FIXTURES/corrupt_lzma_body.pbzx" 2>&1); then
    fail "E2: corrupt LZMA body" "expected non-zero exit"
else
    if echo "$stderr" | grep -q "LZMA"; then
        pass "E2: corrupt LZMA body -> LZMA error"
    else
        fail "E2: corrupt LZMA body" "stderr: $stderr"
    fi
fi

# ========== Summary ==========

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
