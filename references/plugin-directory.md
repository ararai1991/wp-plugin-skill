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

Since late 2025, the directory also generates automated security reports after each plugin update — issues surface post-release, not only at submission.

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

1. Confirm and fix promptly — the directory closes plugins with unresolved security issues, and in serious cases the WordPress Security team may push a forced update.
2. Release the fix as a new version and bump the version number.
3. Note the fix in the changelog. Do not hide it — but do not publish exploit details before users have had time to update.
4. Request a CVE through Wordfence or Patchstack if the reporter has not.
5. If the plugin was closed, fix the issue and pass all Plugin Check security checks before requesting relisting.

## Ongoing

- Subscribe to Wordfence Intelligence and Patchstack advisories for your dependencies.
- Keep `Tested up to` current — an unmaintained-looking plugin is a target.
- Enable two-factor authentication on the WordPress.org account. Account compromise is how supply-chain attacks on plugins begin.
- Re-run Plugin Check before every release, not only the first.
