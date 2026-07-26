# Hack The Box - Redeemer

## Overview

**Redeemer** is a beginner Hack The Box Starting Point machine focused on Redis enumeration.

The machine demonstrates how an exposed Redis database with no authentication can allow an unauthenticated user to connect directly to the service, enumerate stored data, and retrieve sensitive information.

The attack path is:

`Nmap -> Redis -> Unauthenticated Access -> Database Enumeration -> Flag`

No software exploit was required. The weakness was that the Redis service was exposed and accessible without authentication.

---

## Initial Enumeration

I started by scanning the target with Nmap.

```bash
nmap -sC -sV <TARGET_IP>
```

The important result was:

```text
6379/tcp open redis
```

Port `6379` is the default port used by Redis.

Once Redis was identified, the next step was to connect to the service and determine whether authentication was required.

---

## What Is Redis?

**Redis** stands for Remote Dictionary Server.

It is an in-memory data store commonly used for:

- Caching
- Session storage
- Application data
- Queues
- Counters
- Temporary data

Unlike a traditional relational database, Redis primarily stores information using key-value structures.

A simplified example might look like:

```text
username -> admin
session  -> abc123
visits   -> 500
```

Redis supports additional data structures, but understanding the key-value concept is enough to begin enumerating the service.

---

## Connecting to Redis

I connected using `redis-cli`:

```bash
redis-cli -h <TARGET_IP>
```

The connection succeeded without requiring credentials.

The prompt changed to something similar to:

```text
<TARGET_IP>:6379>
```

This confirmed that I could communicate directly with the Redis server.

---

## Testing the Connection

A simple Redis command is:

```text
PING
```

The server should respond:

```text
PONG
```

This confirms that the Redis service is responding correctly.

---

## Redis Enumeration

I used:

```text
INFO
```

to retrieve information about the Redis instance.

This can reveal details such as:

```text
Redis version
Operating system
Process information
Memory usage
Connected clients
Replication configuration
Database statistics
```

For this machine, the database information was particularly useful.

---

## Enumerating Databases

Redis can contain multiple logical databases.

The `INFO` output showed a database containing stored keys.

I selected the relevant database using:

```text
SELECT 0
```

Redis responded:

```text
OK
```

This changed the active database to database `0`.

---

## Enumerating Keys

To list the keys stored in the selected database, I used:

```text
KEYS *
```

This returned the available key names.

One of the keys was:

```text
flag
```

The name immediately suggested that its value was worth retrieving.

---

## Retrieving the Flag

Redis values can be retrieved using the `GET` command when the key contains a string value.

```text
GET flag
```

The server returned the flag.

Redeemer was complete.

---

# Attack Path

```text
Nmap
  |
  v
6379/tcp
  |
  v
Redis
  |
  v
redis-cli
  |
  v
No authentication
  |
  v
INFO
  |
  v
SELECT database
  |
  v
KEYS *
  |
  v
flag
  |
  v
GET flag
```

---

# Key Lessons

## Enumeration Does Not Stop at the Port Scan

Nmap identified:

```text
6379/tcp open redis
```

That tells us Redis is running, but it does not tell us:

```text
Is authentication required?
What databases exist?
What data is stored?
What permissions do we have?
```

Those questions require service-specific enumeration.

The process was:

```text
Discover Redis
      |
      v
Connect to Redis
      |
      v
Enumerate configuration
      |
      v
Enumerate database
      |
      v
Enumerate keys
      |
      v
Retrieve data
```

---

## Redis Is Not SQL

Redis differs from databases such as MySQL and PostgreSQL.

A relational database might contain:

```text
Database
   |
   v
Tables
   |
   v
Rows
   |
   v
Columns
```

Redis is more commonly approached through keys and values:

```text
Database
   |
   v
Keys
   |
   v
Values
```

That is why commands such as:

```text
KEYS *
GET flag
```

are useful when beginning Redis enumeration.

---

## Know the Service-Specific Client

Different network services often have their own client tools.

For example:

```text
FTP    -> ftp
SMB    -> smbclient
SSH    -> ssh
Redis  -> redis-cli
```

For Redis:

```bash
redis-cli -h <TARGET_IP>
```

provides an interactive interface for communicating with the server.

Recognizing a service from Nmap and knowing which client can interact with it is an important enumeration skill.

---

## Exposed Databases Can Leak Sensitive Data

Redis is often used internally by applications.

It may contain information such as:

```text
Session tokens
User information
Cached application data
Credentials
API data
Application state
```

An exposed Redis server therefore has the potential to reveal much more than a simple flag.

The important weakness on Redeemer was not Redis itself.

The problem was:

```text
Redis exposed to the network
        +
No authentication
        =
Unauthenticated database access
```

---

## Misconfiguration Can Be Enough

Redeemer did not require:

```text
A CVE
A reverse shell
Password cracking
Privilege escalation
```

The service configuration itself provided access.

This is similar to the lessons from the earlier Starting Point machines:

```text
Meow
Telnet -> unauthenticated root access

Fawn
FTP -> anonymous file access

Dancing
SMB -> accessible network share

Redeemer
Redis -> unauthenticated database access
```

These machines demonstrate why basic service enumeration is important before moving on to complicated exploitation techniques.

---

# Useful Redis Commands

Connect to a remote Redis server:

```bash
redis-cli -h <TARGET_IP>
```

Test connectivity:

```text
PING
```

Retrieve server information:

```text
INFO
```

Select a database:

```text
SELECT 0
```

List keys:

```text
KEYS *
```

Retrieve a string value:

```text
GET <key>
```

Check the type of a key:

```text
TYPE <key>
```

Exit:

```text
QUIT
```

---

# Defensive Notes

Redis should not be unnecessarily exposed to untrusted networks.

Access should be restricted using network controls such as firewall rules and private network segmentation.

Authentication and appropriate Redis access controls should also be configured when required.

Administrators should consider Redis data sensitive even when the service is being used only as a cache because application secrets, sessions, and other valuable information may be stored there.

A network scan can reveal exposed Redis instances:

```bash
nmap -sC -sV <TARGET_IP>
```

Unexpected exposure of:

```text
6379/tcp
```

should be investigated.

---

# Skills Practiced

- Nmap scanning
- TCP port enumeration
- Redis
- `redis-cli`
- Service-specific enumeration
- Redis databases
- Redis keys and values
- Database enumeration
- Unauthenticated service access
- Security misconfiguration analysis

---

## Disclaimer

This writeup documents techniques used in an authorized Hack The Box lab environment for educational purposes.
