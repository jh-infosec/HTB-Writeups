#!/bin/bash
#
# salt-length-bruteforce.sh
#
# HTB Academy bash scripting exercises sometimes ask you to compute a "salt" value
# as the character count of a variable after N rounds of base64 encoding, then use
# that value as an OpenSSL decryption passphrase. The exact character count is
# extremely sensitive to small scripting choices that are easy to get wrong:
#
#   1. `echo "$var"` vs `echo -n "$var"`   (adds vs suppresses trailing newline)
#   2. `base64` (default 76-char line wrap) vs `base64 -w0` (no wrap)
#   3. `${#var}` vs `echo "$var" | wc -c`  (does/doesn't count the trailing newline)
#
# This script tests all combinations and reports the resulting length for each,
# so you can quickly identify which convention a given exercise expects instead
# of guessing and burning submission attempts.
#
# Usage:
#   ./salt-length-bruteforce.sh "<initial_var>" <iterations>
#
# Example:
#   ./salt-length-bruteforce.sh "9M" 28

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <initial_var> <iterations>"
    exit 1
fi

INIT_VAR="$1"
ITERATIONS="$2"

run_variant() {
    local echo_flag="$1"
    local wrap_flag="$2"
    local var="$INIT_VAR"

    for ((i=1; i<=ITERATIONS; i++)); do
        if [[ "$wrap_flag" == "wrap" ]]; then
            var=$(echo $echo_flag "$var" | base64)
        else
            var=$(echo $echo_flag "$var" | base64 -w0)
        fi
    done

    local len_hash="${#var}"
    local len_wc
    len_wc=$(echo "$var" | wc -c)

    echo "echo_flag='${echo_flag:-<none>}' wrap='${wrap_flag}'  ->  \${#var}=${len_hash}   wc -c=${len_wc}"
}

echo "Testing all echo/wrap/counting combinations after $ITERATIONS iterations of base64 on '$INIT_VAR':"
echo
run_variant ""   "wrap"
run_variant "-n" "wrap"
run_variant ""   "nowrap"
run_variant "-n" "nowrap"
echo
echo "Try each resulting number as your 'salt' answer in order until one is accepted or,"
echo "if the exercise has an OpenSSL decrypt step, until one actually decrypts successfully."
