# Hack The Box - TwoMillion

## Overview

**TwoMillion** is a Linux Hack The Box machine based on an older version of the Hack The Box website.

The machine involved web enumeration, JavaScript analysis, interacting with a web API, manipulating account privileges, command injection, gaining a Linux foothold, and eventually escalating privileges.

One of the main lessons from this machine was that useful attack surface is not always visible directly in the browser. Inspecting client-side JavaScript and understanding how the application communicates with its API revealed functionality that could be tested directly.

---

## Initial Enumeration

I started by enumerating the target and identifying the exposed services.

The main attack surface was the web application.

Because the application relied heavily on JavaScript and API requests, normal directory enumeration was only part of the process. Understanding how the front end communicated with the backend became important.

---

## Invite Page

The website required an invite code before an account could be registered.

Rather than treating the invite system as a black box, I inspected the JavaScript loaded by the page.

This revealed functionality related to the invite process and showed that the browser was communicating with API endpoints behind the scenes.

This was an important reminder that client-side JavaScript can expose:

- API endpoints
- HTTP methods
- Request formats
- Hidden functionality
- Application logic

The browser interface may hide functionality that is still accessible through the underlying API.

---

## Invite Code Generation

After investigating the invite functionality, I was able to interact with the API and obtain the information needed to generate an invite code.

The invite code allowed me to register a normal account and authenticate to the application.

At this point, I had moved from an unauthenticated visitor to an authenticated user, which exposed additional API functionality.

---

## API Enumeration

Once authenticated, I began investigating the application's API more closely.

Instead of only clicking through the website, I looked at the available endpoints and tested how the backend responded to different requests.

The important distinction here was understanding that discovering an endpoint is only the first step.

An API endpoint may behave differently depending on:

- The HTTP method used
- Authentication state
- Request parameters
- JSON data supplied in the request body
- The privileges of the current account

This meant that endpoints had to be tested and understood rather than simply requested once.

---

## Privilege Escalation to Admin

During API enumeration, I discovered functionality related to user administration.

By manipulating the appropriate API request, it was possible to change the privileges associated with my account.

I was then able to confirm that the account had gained administrative access.

This was an application-level privilege escalation rather than Linux privilege escalation.

The progression at this stage was:

```text
Normal web user
      |
      v
API enumeration
      |
      v
Admin functionality discovered
      |
      v
Request manipulation
      |
      v
Administrative web user
```

This demonstrated an important access-control problem.

A web application should not rely on the user interface to prevent normal users from accessing privileged functionality. Authorization must be enforced by the backend for every sensitive request.

---

## Administrative API

Administrative access exposed additional API functionality.

One particularly interesting feature was related to VPN generation.

The application accepted user-controlled data that was eventually processed by the underlying operating system.

Testing this functionality revealed that the input was not being handled safely.

---

## Command Injection

The VPN-related functionality was vulnerable to command injection.

User-controlled input could influence a command executed by the server.

Conceptually, the vulnerability looked like:

```text
User input
    |
    v
API request
    |
    v
Backend processing
    |
    v
Operating system command
    |
    v
Command injection
```

After confirming that commands could be executed, the next objective was to turn the vulnerability into an interactive foothold on the target.

---

## Initial Foothold

The command injection vulnerability provided a path from the web application into the underlying Linux system.

At this point, the attack had crossed an important boundary:

```text
Web application access
        |
        v
Administrative API access
        |
        v
Command injection
        |
        v
Operating system access
```

From here, I began normal Linux enumeration to understand the environment, available users, configuration files, credentials, permissions, and possible privilege escalation paths.

---

## Linux Enumeration

After obtaining access to the system, I enumerated the host for information that could help move from the web application's execution context to a more useful user account.

Areas worth investigating included:

```text
Application configuration
Environment variables
Credentials
User accounts
Home directories
Running services
File permissions
Sudo permissions
System version
Installed software
```

Application configuration is particularly important after compromising a web application because backend services frequently require credentials for databases or other internal resources.

Those credentials may also have been reused elsewhere.

---

## User Access

Further enumeration provided a path to a normal Linux user account.

This gave more stable access to the machine and allowed the privilege escalation stage to be investigated separately from the original web vulnerability.

The attack chain had now progressed through several different security boundaries:

```text
Unauthenticated web visitor
        |
        v
Registered user
        |
        v
Administrative web user
        |
        v
Command execution
        |
        v
Linux user
```

---

## Privilege Escalation

The final stage involved investigating the Linux system for a path from the compromised user to root.

This stage reinforced the importance of treating initial access and privilege escalation as separate problems.

A remote code execution vulnerability does not necessarily provide root privileges immediately. Once access is obtained, the host needs to be enumerated again from the perspective of the compromised account.

---

## Attack Chain

The overall path through TwoMillion was:

```text
Nmap / Recon
      |
      v
Web Application
      |
      v
Invite Page
      |
      v
JavaScript Analysis
      |
      v
Invite API
      |
      v
Account Registration
      |
      v
Authenticated API Enumeration
      |
      v
Privilege Manipulation
      |
      v
Administrative Web Access
      |
      v
VPN API
      |
      v
Command Injection
      |
      v
Linux Foothold
      |
      v
User Access
      |
      v
Privilege Escalation
      |
      v
Root
```

---

## Key Takeaways

TwoMillion was useful because the attack chain involved several different layers rather than relying on one vulnerability.

### Client-side code is useful reconnaissance

JavaScript can reveal API routes and application behavior that may not be obvious from the rendered website.

### APIs should be tested directly

The web interface is only one client for an API. Understanding the underlying HTTP requests makes it possible to test the backend independently.

### Authentication and authorization are different

Being authenticated proves who a user is.

Authorization determines what that user is allowed to do.

Sensitive backend functionality must enforce authorization regardless of whether the normal user interface exposes it.

### Administrative access to an application is not necessarily system access

Gaining administrative privileges inside the web application opened additional functionality, but another vulnerability was still required to reach the operating system.

### Initial access is not the end

After obtaining command execution, the machine had to be enumerated again to find a path through user access and eventually root privileges.

---

## Skills Practised

This machine involved:

- Network enumeration
- Web application enumeration
- JavaScript analysis
- API discovery
- HTTP request analysis
- Authentication testing
- Authorization testing
- API privilege escalation
- Command injection
- Linux enumeration
- Credential discovery
- Privilege escalation

TwoMillion was particularly useful for understanding how weaknesses at several different layers can be chained together to turn basic web access into full system compromise.
