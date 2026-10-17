# WordPress Security Assessment: Small Business Photography Site

**Date:** 17 October 2026
**Type:** Authorised assessment of my own production site (identification and remediation only, no exploitation)

## Summary

The assessment found 6 real vulnerabilities on the live site, including an unauthenticated SQL injection with no vendor fix, and all 6 were remediated the same day. A WPScan run against a local replica of the site flagged 9 issues across the PhotoMe theme and 4 plugins. 2 were false positives caused by version detection on the replica, and 1 did not apply to the installed version.

Remediation removed 16 of 31 plugins (including every vulnerable plugin without a fix) and updated the theme from 5.6.14 to 5.7.2. It also unpublished 78 leftover theme demo pages. The site was retested afterwards and all pages, the contact form and the galleries still work.

## Scope and method

The target runs WordPress 7.1.3 on shared hosting behind Cloudflare.

1. **Direct scan blocked.** WPScan against the live site returned 403 from the Cloudflare web application firewall, including with `--random-user-agent`. Forcing the scan through would only have produced 403s.
2. **Built a local replica.** A Duplicator package of the site, excluding media and unrelated sites hosted in subfolders (about 460 MB of files and a 44 MB database), was restored on Kali in Docker. The backup was password-protected and deleted from the server right after download.
3. **Scanned the replica.** WPScan 4.1.0 with a vulnerability database API token.
4. **Triaged each finding** against the versions actually installed on the live site, then remediated on the live site and retested it.

### Lab setup

```yaml
# docker-compose.yml
services:
  db:
    image: mariadb:11
    environment:
      MARIADB_ROOT_PASSWORD: root
      MARIADB_DATABASE: wp
      MARIADB_USER: wp
      MARIADB_PASSWORD: wp
  web:
    image: wordpress:php8.3-apache   # matches the live site's PHP 8.3
    ports: ["8080:80"]
    volumes: ["./site:/var/www/html"]
    depends_on: [db]
```

```bash
wpscan --url http://localhost:8080 --api-token "$WPSCAN_TOKEN" \
  -e vp,vt,u --plugins-detection mixed
```

## Findings

Severity is my own assessment, based on whether an attacker needs a login and whether a fix exists.

| # | Component (installed) | Issue | CVE | Login needed | Assessed severity | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Creative Mail 1.6.9 | SQL injection (no fix released) | CVE-2026-3430 | None | Critical | Plugin deleted |
| 2 | PhotoMe theme 5.6.14 | Server-side request forgery, fixed in 5.7.2 | CVE-2026-24381 | None | High | Updated to 5.7.2 |
| 3 | PhotoMe theme 5.6.14 | Stored cross-site scripting, fixed in 5.7.2 | CVE-2026-24949 | None | High | Updated to 5.7.2 |
| 4 | Creative Mail 1.6.9 | SQL injection (no fix released) | CVE-2026-65547 | Subscriber | High | Plugin deleted |
| 5 | Slider Revolution 6.7.29 | Arbitrary file read, fixed in 6.7.37 | CVE-2025-9217 | Contributor | Medium | Plugin deleted (unlicensed, could not update) |
| 6 | Slider Revolution 6.7.29 | Arbitrary file read, fixed in 6.7.38 | CVE-2025-10249 | Contributor | Medium | Plugin deleted |
| 7 | PhotoMe theme 5.6.14 | PHP object injection, affects 5.6.11 and below | CVE-2025-69301 | None | Not applicable | Installed version outside affected range |
| 8 | Host management plugin | Authentication bypass, fixed in 4.19.1 | CVE-2026-80099 | None | False positive | Live site runs 4.21.0; version undetectable on replica |
| 9 | Akismet | Stored cross-site scripting in 2.5.0 to 3.1.4 | CVE-2015-9357 | None | False positive | Live site runs 5.7.2; version undetectable on replica |

## Other observations

- **XML-RPC enabled** (`/xmlrpc.php`): a common target for password guessing and pingback abuse if nothing uses it.
- **WordPress readme exposed** (`/readme.html`): confirms the site runs WordPress.
- **External WP-Cron reachable** (`/wp-cron.php`): can be called repeatedly to add server load.
- **Must-use plugins folder present**: two host-managed plugins, worth knowing about when auditing.
- **User enumeration not completed**: the scan was stopped before the user name check.

## Remediation and attack surface reduction

The site went from 31 plugins and 84 published pages to 15 plugins and 6 pages. Every change was checked against all 263 live URLs before anything was deleted.

1. **Deleted Creative Mail first**, on its own, because the unauthenticated SQL injection had no fix.
2. **Deactivated 16 unused plugins, then retested before deleting them.** They included Slider Revolution, a remote staging connector, a backup plugin, two form builders and a popup builder. None was used by any page.
3. **Updated PhotoMe from 5.6.14 to 5.7.2** after taking a zip backup of the theme folder.
4. **Unpublished 78 theme demo pages** left over from the theme's demo import. They were public, indexable, and full of stock photos and placeholder text.
5. **Retested the live site:** all main pages return 200 with no PHP errors, and the gallery, lightbox, map and contact form all work. The theme now reports version 5.7.2.

## Lessons learned

- **Secrets leaked into working notes.** WordPress authentication keys and salts (shown by the restore installer) and API tokens were pasted into a chat log. All of them were treated as compromised and scheduled for rotation.
- **A WAF is a real control.** Cloudflare stopped an automated scanner outright, and testing a replica is the right answer rather than forcing past it.
- **Version detection is not proof.** Two findings were false positives because the replica hid plugin versions; triage against the real installed versions mattered.
- **Scope the backup.** The first package was 2.72 GB because other sites lived in subfolders; on a nearly full host, building it could have filled the disk and taken email and every hosted site down.
- **Size the lab.** Aggressive plugin detection against a local Docker stack, in a VM given 9.7 GB of RAM, starved the host machine. Passive detection with 2 threads, and a smaller VM, is the sustainable setup.

## Outstanding actions

- [ ] Rotate the WordPress authentication keys and salts on the live site
- [ ] Regenerate the WPScan API token
- [ ] Delete the theme backup zip from the server
- [ ] Update the replica the same way, then rescan with `--plugins-detection passive -t 2` to confirm a clean result and finish the user enumeration check
- [ ] Disable XML-RPC if nothing uses it, and block public access to `readme.html`
- [ ] Turn on two-factor login for admin accounts

## References

Advisory links as reported by WPScan:

1. [Creative Mail unauthenticated SQL injection](https://wpscan.com/vulnerability/eb2f34bd-c626-4831-a886-c82882073bcd)
2. [PhotoMe server-side request forgery](https://wpscan.com/vulnerability/064f4c3f-d225-4db4-b12d-5fb51d6c8404)
3. [PhotoMe stored cross-site scripting](https://wpscan.com/vulnerability/73b61f3b-1cbb-439c-8ad4-cdafa2ef6927)
4. [Creative Mail subscriber SQL injection](https://wpscan.com/vulnerability/57bed168-420b-4c39-9977-68575693ab9a)
5. [Slider Revolution file read (6.7.37 fix)](https://wpscan.com/vulnerability/25b1c8f2-117f-448b-9a95-790db3422d6e)
6. [Slider Revolution file read (6.7.38 fix)](https://wpscan.com/vulnerability/64158e5e-8cc8-4a56-89fc-8e4f87df0d0b)
7. [PhotoMe PHP object injection](https://wpscan.com/vulnerability/23521b42-8057-426d-ada5-f0c151afd0cf)
8. [Host management plugin authentication bypass](https://wpscan.com/vulnerability/a676c082-1c48-45b8-9bc0-4172962aecb9)
9. [Akismet stored cross-site scripting](https://wpscan.com/vulnerability/1a2f3094-5970-4251-9ed0-ec595a0cd26c)
