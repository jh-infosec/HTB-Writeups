# Hack The Box - Orion

## Overview

**Orion** is a Linux Hack The Box machine where the initial attack surface was a web application running on port 80.

The early stages of the machine involved service enumeration, virtual host configuration, directory discovery, application fingerprinting, and vulnerability research against Craft CMS.

This writeup documents my actual enumeration and troubleshooting process rather than only the final attack path.

---

## Initial Enumeration

I started by scanning the target with Nmap.

The target IP during my session was:

```text
10.129.43.146
```

The scan identified two main services:

```text
22/tcp - SSH
80/tcp - HTTP
```

The HTTP service redirected requests to:

```text
http://orion.htb/
```

I added the hostname to `/etc/hosts` so the application could be accessed using its expected virtual host.

---

## Web Enumeration

After accessing the site, I began enumerating the web application.

I used `ffuf` with the common DIRB wordlist:

```bash
ffuf -w /usr/share/dirb/wordlists/common.txt -u http://orion.htb/FUZZ
```

Some of the interesting results included:

```text
.htaccess       403
.git/HEAD       403
admin           302
assets          301
logout          302
index           200
index.php       200
```

The `/admin` endpoint was particularly interesting because it indicated that the application exposed an administrative interface.

The `.git/HEAD` response also showed that a Git-related path existed, although direct access was forbidden.

---

## Application Fingerprinting

The next challenge was determining what software powered the site.

There was no obvious WordPress-style generator tag or immediately visible version information, so I inspected the application and its page source more closely.

This led to the identification of:

```text
Craft CMS 5.6.16
```

Knowing the exact CMS and version changed the direction of the enumeration. Instead of treating the target as an unknown PHP application, I could investigate vulnerabilities affecting that specific Craft CMS release.

---

## Vulnerability Research

With Craft CMS 5.6.16 identified, I searched the local Exploit-DB database using SearchSploit:

```bash
searchsploit craft cms
```

This revealed relevant Craft CMS vulnerability research and led into investigating whether the installed version could be exploited for remote code execution.

At this point, the attack moved from general web enumeration into vulnerability analysis of the CMS.

---

## Key Takeaways

This stage of Orion reinforced several important enumeration concepts:

- A small number of open ports does not mean a small attack surface.
- HTTP redirects can reveal the hostname expected by a virtual host.
- Directory enumeration can expose important application endpoints such as administrative panels.
- Fingerprinting the underlying CMS and its exact version can significantly narrow vulnerability research.
- Enumeration should come before exploitation. Identifying the application properly makes vulnerability research much more targeted.

The next stage of the machine involved investigating the Craft CMS attack surface and determining a path to remote code execution.
