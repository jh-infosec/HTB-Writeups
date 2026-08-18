# Crocodile - HTB Write-up

> **Scope note:** This write-up documents an authorized Hack The Box lab.

## Summary

Crocodile is a very easy Linux machine that demonstrates the dangers of misconfigured authentication and sensitive information exposure.

The attack begins with network enumeration, where we discover an FTP service allowing anonymous authentication. The FTP server contains two files holding usernames and passwords in clear text.

We then enumerate the HTTP service and use Gobuster to discover a hidden `login.php` endpoint. The credentials recovered from the FTP server allow us to authenticate to the web application and obtain the flag.

    -> Nmap enumeration
    -> FTP discovered on port 21
    -> Anonymous FTP login
    -> Download credential files
    -> Recover usernames and passwords
    -> HTTP discovered on port 80
    -> Gobuster finds login.php
    -> Use recovered admin credentials
    -> Access admin panel
    -> Retrieve flag

---

# Enumeration

## Nmap

We begin by scanning the target to identify which ports and services are exposed.

    nmap -sC -sV <TARGET_IP>

The scan reveals two interesting services:

    PORT   STATE SERVICE VERSION
    21/tcp open  ftp     vsftpd 3.0.3
    80/tcp open  http    Apache httpd 2.4.41

Port `21` is running **vsftpd 3.0.3**, while port `80` is running **Apache HTTP Server 2.4.41**.

The Nmap scan also indicates that anonymous FTP login is allowed.

The FTP service therefore becomes the first attack surface to investigate.

---

# FTP Enumeration

## Anonymous Login

We connect to the FTP service:

    ftp <TARGET_IP>

When prompted for a username, we use:

    anonymous

The server accepts the connection without requiring a normal user account.

The FTP server returns:

    230 Login successful.

We can now enumerate the contents of the FTP server.

---

## Listing Files

Inside the FTP session, we run:

    ls

Two files are available:

    allowed.userlist
    allowed.userlist.passwd

These files are particularly interesting because they appear to contain usernames and passwords.

---

## Downloading the Files

The FTP `get` command allows us to download files from the remote server.

We download both files:

    get allowed.userlist
    get allowed.userlist.passwd

We then exit the FTP session:

    bye

The files are now available on our Kali machine.

---

# Credential Enumeration

## allowed.userlist

We examine the username list:

    cat allowed.userlist

The file contains several usernames, including:

    admin

The `admin` account is particularly interesting because it suggests a higher-privilege web account.

---

## allowed.userlist.passwd

We then examine the password file:

    cat allowed.userlist.passwd

This contains several passwords corresponding to the usernames in the previous file.

The credentials that ultimately prove useful are:

    admin:rKXM59ESxesUFHAd

We now have valid credentials, but we still need to determine where they can be used.

---

# Web Enumeration

## Apache

Port `80` is running Apache HTTP Server `2.4.41`.

We can visit the target in a web browser:

    http://<TARGET_IP>/

The main website does not immediately reveal an obvious login page.

Because hidden files and directories may contain administrative functionality, we perform directory enumeration.

---

## Gobuster

We use Gobuster to search for directories and PHP files:

    gobuster dir -u http://<TARGET_IP>/ -w /usr/share/seclists/Discovery/Web-Content/common.txt -x php

The `-x` switch tells Gobuster to also test for files with the specified extension.

An interesting result appears:

    /login.php

This gives us a clear location where the credentials recovered from the FTP server can be tested.

---

# Web Authentication

We navigate to:

    http://<TARGET_IP>/login.php

A login page is presented asking for a username and password.

We use the credentials discovered earlier:

    Username: admin
    Password: rKXM59ESxesUFHAd

The credentials are accepted and we gain access to the administrative panel.

---

# Flag

After successfully authenticating to the admin panel, the flag is displayed.

    c7110277ac44d78b6a9fff2232434d16

This completes the machine.

---

# Attack Path

    Target
      |
      v
    Nmap Scan
      |
      +-------------------+
      |                   |
      v                   v
    FTP :21            HTTP :80
      |                   |
      v                   v
    Anonymous FTP      Web Enumeration
      |                   |
      v                   v
    Credential Files    Gobuster
      |                   |
      v                   v
    Username +          login.php
    Password              |
      |                   |
      +---------+---------+
                |
                v
          Admin Credentials
                |
                v
          Admin Web Panel
                |
                v
               Flag

---

# Key Takeaways

- Always begin with service enumeration to understand the attack surface.
- Anonymous FTP access can expose sensitive information if the service is misconfigured.
- Sensitive files should never contain plaintext usernames and passwords.
- Information discovered on one service can often be used against another service.
- The FTP service provided the credentials, while the HTTP service provided the login interface.
- Gobuster's `-x` switch is useful when looking for specific file extensions such as `.php`.
- The hidden `login.php` endpoint provided the foothold into the administrative interface.
- This machine demonstrates how two seemingly separate weaknesses can be chained together:

    FTP Misconfiguration
            +
    Sensitive Credential Exposure
            +
    Hidden Web Login
            =
    Administrative Access
