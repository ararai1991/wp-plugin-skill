# WordPress.org Directory Readiness

Security requirements and conventions for submitting a plugin to the WordPress.org directory, or relisting one that was pulled.

## Plugin Check is mandatory

The official **Plugin Check (PCP)** plugin runs most of the checks the review team uses. **All Security-category checks must pass** for new submissions and for relisting a plugin that was closed for security issues.

```bash
# As a WP-CLI command
wp plugin install plugin-check --activate
wp plugin check <your-plugin-slug>

# Security category only
wp plugin check <your-plugin-slug> --categories=security
```

Plugin Check combines PHPCS sniffs (PHPCompatibility, WordPress-Core, WordPress-Docs, and the `WordPress.Security.*` sniffs from WordPress-Extra) with custom static checks and some runtime checks that activate the plugin and fire hooks.

## Every release is security-reviewed — and can be blocked

Since late 2025 the directory generated security reports after each update. In 2026 that became a gate:

- **June 5, 2026** — every plugin release enters a **6-hour cooldown** before it is distributed through the update API.
- **September 9, 2026** — during that window, releases are scanned by several AI models together with Jetpack Scan. **High-risk releases are blocked automatically** and not distributed until fixed. Committers get an email with the findings.

What it flags is exactly what this skill's security reference covers: unescaped output, missing capability checks, SQL injection risk, unsafe deserialization, and unsafe file operations. It also catches planted backdoors — one was stopped 26 minutes after commit in July 2026.

What this means in practice:

- **A security bug now blocks your release**, not just a later report. Run Plugin Check and `scripts/wp-plugin-audit.sh` *before* tagging.
- **Hotfixes take at least 6 hours to reach users.** Plan emergency releases accordingly, and never rely on "we'll push a fix in ten minutes".
- **If blocked:** read the findings, fix, and publish a new release. Resubmitting a fix is typically faster than disputing a finding; contact the Plugins Team only when a finding is genuinely wrong.
- No email means no action needed.

## Security-relevant guideline requirements

**Unique prefix on everything public.** Every function, class, constant, namespace, option, meta key, database table, global variable, and script/style handle needs a distinctive prefix (four characters or more; `wp_` is reserved). Generic names collide with other plugins, and collisions become security bugs.

```php
// Bad
function get_settings() {}
define( 'VERSION', '1.0' );
update_option( 'settings', $v );

// Good
function myplugin_get_settings() {}
define( 'MYPLUGIN_VERSION', '1.0' );
update_option( 'myplugin_settings', $v );
```

**No remote code loading.** The plugin must not fetch and execute code from an external server. All executable code ships in the plugin. This is a hard rule — it exists precisely because it is the supply-chain attack vector.

**No obfuscated code.** Code must be human-readable. Minified or obfuscated PHP is rejected; ship the unminified source.

**No tracking or data collection without consent.** Phoning home with site data requires explicit opt-in, with what is collected disclosed.

**Sanitize, escape, and validate.** The guidelines require it explicitly; Plugin Check's security sniffs enforce much of it.

**No unauthorized changes to the site.** No injecting links into the front end, no modifying other plugins, no altering admin screens outside the plugin's own area.

**Respect trademarks and naming.** Do not use another project's name as a prefix or in a way implying affiliation.

**Serve assets locally.** Do not load scripts, styles, or fonts from third-party CDNs — bundle them. (Remote assets are a supply-chain and privacy risk.)

**Include a license.** GPLv2 or later, or a compatible license, and all bundled libraries must be compatible.

## Pre-submission checklist

- [ ] Plugin Check passes with zero Security-category errors
- [ ] `scripts/wp-plugin-audit.sh` shows no unexplained critical hits — a flagged release is now blocked, not just reported
- [ ] `Requires PHP` is 7.4 or higher (WordPress 7.0 dropped PHP 7.2 and 7.3; 8.3 is recommended)
- [ ] `readme.txt` valid, with accurate `Requires at least`, `Tested up to`, `Requires PHP`
- [ ] Main file header complete: Plugin Name, Description, Version, Author, License, Text Domain
- [ ] `defined( 'ABSPATH' ) || exit;` at the top of every PHP file
- [ ] Unique prefix on every public-namespace symbol
- [ ] No hardcoded secrets or credentials in source
- [ ] No `error_log` / `var_dump` / `print_r` debug output left in
- [ ] No remote code execution or remotely loaded scripts
- [ ] All third-party libraries bundled, current, GPL-compatible, and attributed
- [ ] Uninstall handled via `uninstall.php` or `register_uninstall_hook()` — and it checks `WP_UNINSTALL_PLUGIN`
- [ ] Activation/deactivation hooks do not leave privileged state behind
- [ ] Text domain matches the slug; all user-facing strings translatable and escaped
- [ ] No PHP notices/warnings with `WP_DEBUG` on
- [ ] Tested against the current WordPress version

## `uninstall.php` safety

```php
<?php
// Must bail if not invoked by WordPress's uninstall routine
defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

delete_option( 'myplugin_settings' );
delete_site_option( 'myplugin_network_settings' );

// Multisite: clean every site, not just the current one
if ( is_multisite() ) {
    foreach ( get_sites( array( 'fields' => 'ids' ) ) as $blog_id ) {
        switch_to_blog( $blog_id );
        delete_option( 'myplugin_settings' );
        restore_current_blog();
    }
}
```

## Handling a reported vulnerability

Speed matters more than it used to: the median time from public disclosure to mass exploitation of a high-impact WordPress plugin bug was **5 hours** in 2025, and 46% of vulnerabilities had no fix available at disclosure.

1. Confirm and fix promptly — the directory closes plugins with unresolved security issues, and in serious cases the WordPress Security team may push a forced update.
2. Release the fix as a new version and bump the version number. Remember the 6-hour release cooldown.
3. Note the fix in the changelog. Do not hide it — but do not publish exploit details before users have had time to update.
4. Request a CVE through Wordfence or Patchstack if the reporter has not.
5. If the plugin was closed, fix the issue and pass all Plugin Check security checks before requesting relisting.
6. If the flaw is **actively exploited** and you are in scope of the EU Cyber Resilience Act, the reporting clock is already running — see below.

## EU Cyber Resilience Act

The CRA applies to **products with digital elements made available on the EU market in the course of a commercial activity** — which includes paid plugins and themes sold to anyone in the EU, wherever the vendor is based. Purely non-commercial open-source plugins are generally out of scope; open-source *stewards* (organizations that systematically support open-source products used commercially) carry lighter obligations and cannot be fined. If you monetize a plugin — paid tiers, licenses, a freemium upsell — treat yourself as in scope and get proper advice.

**From 11 September 2026 — reporting obligations apply:**

| When you become aware of… | Deadline | What |
|---|---|---|
| An actively exploited vulnerability, or a severe incident | **24 hours** | Early warning via ENISA's single reporting platform |
| | **72 hours** | Notification: technical details, mitigations, indicators of compromise |
| | 14 days after a fix (vulnerability) / 1 month (incident) | Final report |

Users must also be informed. The clock starts when **you** become aware — not when a regulator contacts you.

**What to have in place now** (small-vendor minimum):

- A monitored security contact address
- `/.well-known/security.txt` (RFC 9116) on your site, pointing to it
- A published coordinated vulnerability disclosure policy
- A one-page internal procedure: who decides "actively exploited", who holds the ENISA account, message templates for 24h/72h/final reports, how users are notified
- A software bill of materials — at least your top-level dependencies (`composer.json`, `package.json`, bundled libraries)
- A way to monitor those dependencies for new vulnerabilities

**From 11 December 2027 — full obligations:** security-by-design requirements (Annex I), technical documentation, EU declaration of conformity, CE marking, and a defined security-support period (typically at least five years). Penalties reach €15 million or 2.5% of worldwide turnover.

This is a summary, not legal advice.

## Ongoing

- Subscribe to Wordfence Intelligence and Patchstack advisories for your dependencies.
- Keep `Tested up to` current — an unmaintained-looking plugin is a target.
- Enable two-factor authentication on the WordPress.org account. Account compromise is how supply-chain attacks on plugins begin.
- Re-run Plugin Check before every release, not only the first.
