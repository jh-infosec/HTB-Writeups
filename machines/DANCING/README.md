# Hack The Box - Dancing

## Overview

**Dancing** is a beginner Hack The Box Starting Point machine focused on SMB enumeration and Windows network shares.

The machine demonstrates how an exposed SMB service can reveal accessible shares and how a poorly configured share can allow access without valid user credentials.

The attack path is:

`Nmap -> SMB -> Share Enumeration -> Anonymous Access -> WorkShares -> Flag`

The main lesson from Dancing is that discovering an open service is only the beginning. Once SMB is identified, the next step is to enumerate the resources that service exposes.

---

## Initial Enumeration

I started by scanning the target with Nmap.

```bash
nmap -sC -sV <TARGET_IP>
```

The scan revealed SMB-related services, including:

```text
135/tcp open  msrpc
139/tcp open  netbios-ssn
445/tcp open  microsoft-ds
```

Port `445/tcp` was particularly important because it indicated that SMB was available on the target.

---

## What Is SMB?

**SMB**, or Server Message Block, is a network protocol commonly used by Windows systems for sharing resources.

SMB can provide access to:

- Files
- Directories
- Printers
- Named pipes
- Other network resources

A shared directory exposed through SMB is known as a **share**.

For example, a Windows machine might expose:

```text
\\SERVER\Documents
```

where `Documents` is the share name.

From Linux, tools such as `smbclient` can interact with these shares.

---

## Enumerating SMB Shares

After discovering SMB, I used `smbclient` to enumerate the shares exposed by the target.

```bash
smbclient -L //<TARGET_IP>/ -N
```

The options used here are:

```text
-L    List available shares
-N    Do not prompt for a password
```

The server returned several shares, including:

```text
ADMIN$
C$
IPC$
WorkShares
```

The first three are common Windows administrative shares.

`WorkShares` stood out because it was a custom share and therefore worth investigating.

---

## Windows Administrative Shares

Windows commonly creates several administrative shares automatically.

Examples include:

```text
ADMIN$
C$
IPC$
```

`C$` represents the root of the Windows `C:` drive and normally requires administrative privileges.

`ADMIN$` usually maps to the Windows installation directory.

`IPC$` is used for inter-process communication and various SMB operations.

The custom share:

```text
WorkShares
```

was therefore more interesting from an enumeration perspective.

---

## Accessing WorkShares

I attempted to connect to the share without providing credentials:

```bash
smbclient //<TARGET_IP>/WorkShares -N
```

The connection succeeded.

This provided an SMB prompt:

```text
smb: \>
```

At this point I could enumerate the files and directories available inside the share.

---

## SMB Enumeration

I listed the contents of the share:

```text
smb: \> ls
```

The share contained directories belonging to different users.

I navigated through them using:

```text
smb: \> cd <directory>
```

and listed their contents:

```text
smb: \> ls
```

One of the directories contained:

```text
flag.txt
```

---

## Downloading the Flag

SMB files can be downloaded using the `get` command.

```text
smb: \> get flag.txt
```

This transferred the remote file to my local Kali machine.

I then exited the SMB client:

```text
smb: \> exit
```

Back on Kali, I confirmed the file had downloaded:

```bash
ls
```

and read it:

```bash
cat flag.txt
```

Dancing was complete.

---

# Attack Path

```text
Nmap
  |
  v
445/tcp
  |
  v
SMB
  |
  v
Enumerate shares
  |
  v
WorkShares
  |
  v
No credentials required
  |
  v
Directory enumeration
  |
  v
flag.txt
  |
  v
get flag.txt
```

---

# Key Lessons

## Service Discovery Leads to Service Enumeration

Nmap identified SMB, but that alone did not reveal the sensitive file.

The next step was to ask:

```text
SMB is running. What does it expose?
```

Using:

```bash
smbclient -L //<TARGET_IP>/ -N
```

revealed the available shares.

This reinforces the difference between **discovery** and **enumeration**.

```text
Discovery
   |
   | SMB exists
   v
Enumeration
   |
   | What shares exist?
   | Can I access them?
   | What files do they contain?
   v
Useful information
```

---

## SMB Uses Shares

SMB organizes shared resources using share names.

For example:

```text
\\TARGET\WorkShares
```

can be accessed from Linux with:

```bash
smbclient //TARGET/WorkShares
```

Once connected, the interface behaves similarly to an FTP client.

Useful commands include:

```text
ls
cd
pwd
get
put
exit
```

---

## Anonymous or Guest Access Can Expose Sensitive Files

The important weakness on Dancing was that `WorkShares` could be accessed without valid credentials.

This allowed an unauthenticated user to browse files stored on the server.

The problem was therefore primarily an **access control and configuration issue**, rather than a software exploit.

No CVE was required.

---

## Custom Shares Deserve Attention

Shares such as:

```text
ADMIN$
C$
IPC$
```

are common Windows shares.

A share with an organization-specific name such as:

```text
WorkShares
```

deserves closer inspection because it may contain user-created or business-related data.

During enumeration, unusual resources often provide more useful information than standard system resources.

---

## Port 445 Is Important in Windows Environments

SMB commonly operates over:

```text
445/tcp
```

Older configurations may also involve:

```text
137
138
139
```

through NetBIOS.

Seeing port 445 during a scan should immediately suggest SMB enumeration.

This becomes especially important when working with Windows machines and Active Directory environments.

---

# Useful SMB Commands

List shares without supplying a password:

```bash
smbclient -L //<TARGET_IP>/ -N
```

Connect to a share:

```bash
smbclient //<TARGET_IP>/WorkShares -N
```

List files:

```text
smb: \> ls
```

Change directory:

```text
smb: \> cd <directory>
```

Download a file:

```text
smb: \> get <filename>
```

Exit:

```text
smb: \> exit
```

These commands form a useful foundation for SMB enumeration on later machines.

---

# Defensive Notes

SMB shares should follow the principle of least privilege.

Unauthenticated or guest users should not have access to sensitive directories unless anonymous access is intentionally required.

Administrators should regularly review:

- Which SMB shares exist
- Which users and groups can access them
- Whether guest access is enabled
- Whether users can write to shared directories
- Whether sensitive files are stored in broadly accessible shares

Network exposure should also be considered.

SMB should not be unnecessarily accessible from untrusted networks.

A basic network scan would reveal the exposed service:

```bash
nmap -sC -sV <TARGET_IP>
```

The shares could then be audited to determine whether their permissions match their intended use.

---

# Skills Practiced

- Nmap scanning
- TCP port enumeration
- SMB
- Windows shares
- `smbclient`
- Share enumeration
- Anonymous authentication
- Directory navigation
- File transfer
- Windows administrative shares
- Access control analysis
- Basic Windows network enumeration

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
