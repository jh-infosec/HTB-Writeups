# Hack The Box - Fawn

## Overview

**Fawn** is a beginner Hack The Box Starting Point machine focused on service enumeration and FTP.

The machine demonstrates how an exposed FTP server configured to allow anonymous authentication can expose sensitive files without requiring valid user credentials.

The attack path is:

`Nmap -> FTP -> Anonymous Login -> File Enumeration -> Flag`

Unlike machines that require exploitation or privilege escalation, Fawn is primarily about identifying an exposed service and testing how it is configured.

---

## Initial Enumeration

I started by scanning the target with Nmap.

```bash
nmap -sC -sV <TARGET_IP>
```

The important result was:

```text
21/tcp open ftp
```

Port 21 is commonly associated with **FTP**, or File Transfer Protocol.

The next step was therefore to connect to the FTP service and determine what authentication it required.

---

## FTP Enumeration

I connected using the FTP client:

```bash
ftp <TARGET_IP>
```

The server presented a username prompt.

A common check when FTP is exposed is whether the server allows anonymous authentication.

I entered:

```text
anonymous
```

The server accepted the login without requiring a legitimate user account.

I now had access to the files exposed by the FTP server.

---

## Anonymous FTP

Anonymous FTP is a configuration that allows users to access an FTP server without having an individual account.

Historically, this was sometimes used to distribute public files.

The problem occurs when anonymous access exposes files that were never intended to be public.

The authentication flow on Fawn was effectively:

```text
FTP Server
    |
    v
Username
    |
    v
anonymous
    |
    v
Access Granted
```

No vulnerability exploit was required. The issue was insecure service configuration.

---

## File Enumeration

After authenticating, I listed the available files:

```text
ftp> ls
```

This revealed the flag file.

Before reading it, I needed to transfer it from the remote FTP server to my local machine.

I downloaded it using:

```text
ftp> get flag.txt
```

The FTP client transferred the file into the directory from which I had started the client.

I then exited FTP:

```text
ftp> exit
```

---

## Reading the Flag

Back on my local system, I confirmed the downloaded file existed:

```bash
ls
```

Then read it:

```bash
cat flag.txt
```

Fawn was complete.

---

# Attack Path

```text
Nmap
  |
  v
21/tcp
  |
  v
FTP
  |
  v
Anonymous authentication
  |
  v
Directory listing
  |
  v
flag.txt
  |
  v
get flag.txt
  |
  v
Local file
```

---

# Key Lessons

## Enumeration Before Exploitation

Fawn did not require an exploit.

Nmap revealed FTP, and testing the configuration of that service was enough to gain access.

This reinforces a basic penetration testing workflow:

```text
Discover services
       |
       v
Enumerate services
       |
       v
Identify weaknesses
       |
       v
Exploit when necessary
```

Not every security weakness requires a CVE.

---

## FTP Uses Port 21

FTP commonly listens on:

```text
21/tcp
```

The FTP client can connect using:

```bash
ftp <TARGET_IP>
```

After authentication, common commands include:

```text
ls
get <filename>
put <filename>
pwd
cd <directory>
exit
```

The commands available depend on the permissions granted by the server.

---

## Anonymous Authentication Should Be Tested

When FTP is discovered during an authorized assessment, one useful configuration check is whether anonymous authentication is enabled.

A typical username is:

```text
anonymous
```

If access is granted, the next step is to determine exactly what files and directories the anonymous account can access.

Anonymous access is not automatically a vulnerability. It becomes a security problem when it exposes information or permissions that should not be public.

---

## FTP and SSH Are Different

Fawn focused on FTP, while Meow focused on Telnet.

FTP is primarily designed for transferring files:

```text
Client <------ files ------> FTP Server
```

Remote administration protocols such as SSH provide an interactive shell:

```text
Client <---- commands ----> Server
       <---- output -------
```

Discovering a service therefore does not just tell us which port is open. It tells us what functionality the target is exposing.

---

## FTP Does Not Encrypt Traffic

Traditional FTP does not encrypt its traffic.

Credentials and transferred information can potentially be observed by someone capable of capturing the network traffic.

Secure alternatives include protocols such as SFTP, which operates over SSH.

This becomes particularly relevant in machines such as Cap, where captured FTP traffic can expose credentials.

---

# Defensive Notes

Anonymous FTP should only be enabled when there is a deliberate requirement to provide public file access.

If anonymous access is necessary, permissions should be restricted to the minimum required directories and files.

Sensitive information should never be stored in anonymously accessible locations.

Traditional FTP should also be avoided for sensitive authentication or data transfer because it does not provide encryption.

Regular network scanning can identify exposed services such as FTP:

```bash
nmap -sC -sV <TARGET_IP>
```

Administrators can then verify whether those services are necessary and whether their authentication and permissions are configured correctly.

---

# Skills Practiced

- Nmap scanning
- TCP port enumeration
- FTP
- Anonymous authentication
- Remote directory enumeration
- File transfer
- Basic Linux commands
- Service configuration analysis
- Basic penetration testing methodology

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
