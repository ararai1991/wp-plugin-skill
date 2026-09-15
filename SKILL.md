---
name: wp-plugin-skill
description: Build, review, and ship production-grade WordPress plugins — architecture, hooks, admin pages, settings, custom post types, taxonomies, metadata, users and capabilities, AJAX/REST, HTTP API, cron, shortcodes, blocks, internationalization, privacy, testing, and security hardening. Use when writing any WordPress plugin PHP code, scaffolding a new plugin, adding plugin features, reviewing plugin code for bugs or vulnerabilities, handling $_GET/$_POST, registering AJAX or REST endpoints, running $wpdb queries, or preparing a plugin for the WordPress.org directory.
---

# WordPress Plugin Development

## Overview

This skill covers building WordPress plugins that are correct, secure, maintainable, and directory-ready. It follows the structure of the official [Plugin Handbook](https://developer.wordpress.org/plugins/), with each chapter's practical content in `references/`.

Two rules govern everything else:

**1. Every entry point needs three gates.** Nearly every plugin CVE is a missing gate, not an exotic exploit.

```
Gate 1  AUTHENTICATION  Is this a logged-in user?      is_user_logged_in()
Gate 2  AUTHORIZATION   May THIS user do THIS thing?   current_user_can( 'cap' )
Gate 3  INTENT          Did they mean to, right now?   check_admin_referer()
Then    INPUT           Sanitize + validate every request value
Then    OUTPUT          Escape at the point of printing, per context
```

A nonce without a capability check is not security — it only proves the request came from your form, not that the user is allowed. A capability check without a nonce leaves you open to CSRF. You need both.

**2. Prefix everything and never touch what isn't yours.** Every function, class, constant, option, meta key, table, and handle in the public namespace carries a unique plugin prefix. A plugin shares one global PHP namespace with core and every other active plugin.

## Workflow

### Building a new plugin

0. **Clarify what cannot be inferred** — see "Ask before you build" below. Capability model, public vs. authenticated endpoints, and data storage shape come first; getting them wrong means a rewrite or a vulnerability.
1. **Scaffold** — `references/plugin-basics.md` for the header, file layout, and activation/deactivation/uninstall lifecycle. Pick an architecture (single file, class-based, or a full structure) proportional to the plugin's scope.
2. **Hook in** — `references/hooks.md`. Plugins do everything through actions and filters; get priority and argument count right.
3. **Build the feature** — the relevant reference below.
4. **Gate every entry point** — `references/security.md` and `references/entry-points.md`.
5. **Translate** — wrap every user-facing string from the start; retrofitting i18n is painful (`references/i18n.md`).
6. **Verify** — `references/testing-tools.md`, then run `scripts/wp-plugin-audit.sh`.

### Adding a feature to an existing plugin

Match the existing architecture and prefix conventions before introducing new ones. Read the relevant reference, then apply the three gates to anything that handles a request.

### Reviewing plugin code

1. Run `scripts/wp-plugin-audit.sh <plugin-dir>` for grep-based triage.
2. Walk `references/audit-checklist.md`, ordered by real-world exploitation frequency.
3. For every finding, establish reachability — unauthenticated is critical, admin-only is usually low.
4. Report with file:line, class, who can exploit it, impact, and the fix.

### Preparing for WordPress.org

`references/plugin-directory.md`, then run Plugin Check — all Security-category checks must pass.

## Ask before you build

Some decisions cannot be inferred from a request, and guessing them produces a plugin that is wrong in a way the developer only discovers in production — or a vulnerability. **Ask the developer, then build.**

The rule of thumb: **if getting it wrong means a security hole, data loss, or rewriting the feature, ask. Otherwise pick the sensible default and say what you picked.**

### Always ask

**Who is allowed to do this?** Every feature that writes data, changes settings, or exposes information needs a named capability. "Add a page where users can edit records" does not say whether that means administrators, editors, or any logged-in subscriber — and the difference between `manage_options` and `edit_posts` is the difference between a locked door and an open one.

> Which users should be able to do this? Administrators only (`manage_options`), editors and above (`edit_others_posts`), any author for their own items (`edit_post` + ownership check), or any logged-in user?

**Is this endpoint public?** Before registering `wp_ajax_nopriv_*` or `'permission_callback' => '__return_true'`:

> Should logged-out visitors be able to call this? That makes it a public, unauthenticated endpoint on the open internet.

**Where does this data live?** Post type, taxonomy, post meta, options, or a custom table are not interchangeable — changing later means migrating real data.

> Is this a content item with its own page (custom post type), a label that groups items (taxonomy), a per-item value (meta), or high-volume relational data (custom table)?

**Who owns a record, and can users see each other's?** A capability check alone does not stop one author editing another's item.

> Should users see and edit only their own records, or everyone's?

**Destructive behaviour on uninstall.** Deleting user data is irreversible.

> On uninstall, should the plugin delete its data, or leave it in place in case the plugin is reinstalled?

**Data that identifies a person.** Triggers privacy obligations — see `references/privacy.md`.

> Does this store personal data (emails, IPs, names)? If so it needs export and erasure handlers.

### Ask when it materially changes the work

- **Scale** — "how many records do you expect?" decides meta vs. custom table, and whether pagination is needed.
- **Multisite** — network-activated plugins need per-site handling in activation and uninstall.
- **Minimum WordPress/PHP version** — decides whether modern syntax and newer APIs are available.
- **Editor target** — block editor, classic editor, or both.
- **External services** — an API integration needs to know the auth model and what happens when the service is down.
- **Existing conventions** — when adding to an existing plugin, match its architecture and prefix rather than introducing new ones.

### Don't ask

Don't stall on things with an obvious right answer or a safe default. Choose, state the choice in one line, and keep going:

- Whether to sanitize, escape, use a nonce, or prefix — these are never optional.
- Text domain, file layout, naming conventions — follow the existing plugin or the standard.
- Whether to use `$wpdb->prepare()` — yes.
- Anything already answered in the request, the code, or this skill.

### How to ask

Ask **before writing the affected code**, not after. Group related questions into one exchange rather than interrupting repeatedly. Offer concrete options with a recommendation, since developers often have not thought about the capability model:

> Before I build the delete handler — who should be able to delete records?
> 1. Administrators only (`manage_options`) — safest default
> 2. Editors and above (`delete_others_posts`)
> 3. Any author, own records only (`delete_post` + ownership check)
>
> I'd suggest 3 if end users create these records, 1 if they're site configuration.

If the developer does not answer, or says "you decide", **choose the most restrictive option that still meets the request**, and say so explicitly:

> Defaulting to `manage_options` (administrators only). Loosen it by changing the capability in `myplugin_delete_handler()`.

Restrictive defaults fail closed — a too-tight permission is a support request, a too-loose one is a CVE.

## Reference map

Pick the file matching the task. Each maps to a Plugin Handbook chapter.

| Task | Reference |
|------|-----------|
| Plugin header, file structure, activation/uninstall, architecture | `references/plugin-basics.md` |
| Actions, filters, custom hooks, priority, removing hooks | `references/hooks.md` |
| Capability + nonce + sanitize + escape; the 8 vulnerability classes | `references/security.md` |
| Every HTTP path into plugin code and the gates each needs | `references/entry-points.md` |
| Admin menus, submenus, admin pages | `references/admin-pages.md` |
| Settings API, Options API, settings pages | `references/settings.md` |
| Post meta, meta boxes, register_meta, term/user meta | `references/metadata.md` |
| Custom post types and taxonomies | `references/post-types-taxonomies.md` |
| Roles, capabilities, user meta, user queries | `references/users-roles.md` |
| Enqueuing scripts/styles, AJAX, passing data to JS | `references/javascript-ajax.md` |
| REST API routes, permission callbacks, schema | `references/rest-api.md` |
| Database access, $wpdb, custom tables, dbDelta | `references/database.md` |
| Outbound HTTP requests, transient caching | `references/http-api.md` |
| Scheduled tasks, WP-Cron | `references/cron.md` |
| Shortcodes | `references/shortcodes.md` |
| Blocks and the block editor | `references/blocks.md` |
| Translation functions, text domains, translator comments | `references/i18n.md` |
| Personal data export/erasure, privacy policy | `references/privacy.md` |
| WP_DEBUG, WP-CLI, PHPUnit, Query Monitor, PHPCS | `references/testing-tools.md` |
| Performance: caching, transients, query efficiency | `references/performance.md` |
| Directory submission, Plugin Check, guidelines | `references/plugin-directory.md` |
| Ordered security review checklist with grep patterns | `references/audit-checklist.md` |
| Supply-chain and planted-backdoor detection | `references/backdoor-indicators.md` |

## Non-negotiable rules

These apply to every line of plugin code. Details and code in `references/security.md`.

**Never trust request data.** `$_GET`, `$_POST`, `$_REQUEST`, `$_COOKIE`, `$_FILES`, `$_SERVER` (including `HTTP_REFERER`, `HTTP_X_FORWARDED_FOR`, `REQUEST_URI`). A nonce does not make input trustworthy — it only proves origin.

**Sanitize on input, escape on output, validate before use.** Three separate operations; doing one does not excuse skipping the others. Escape *late*, at the point of printing, choosing the function by context.

**`wp_ajax_nopriv_` and `__return_true` mean unauthenticated.** Register the `nopriv` AJAX variant or a public `permission_callback` only for genuinely public actions.

**`permission_callback` is mandatory** on every REST route, and the check belongs *in* it — not in the route callback.

**Check capabilities, never roles.** `current_user_can( 'manage_options' )`, never `current_user_can( 'administrator' )` or a `$user->roles` comparison.

**Use `$wpdb->prepare()` for every query containing a variable** — and never interpolate into `prepare()`'s first argument. `esc_sql()` is not a substitute.

**Never let user input reach** `eval()`, `assert()`, `create_function()`, `system()`, `exec()`, `shell_exec()`, `passthru()`, `include`/`require` with a variable path, `unserialize()`, `extract()`, or `call_user_func()` with a user-supplied name.

**Prefix everything public** — functions, classes, constants, options, meta keys, tables, script handles, globals. Four characters minimum; `wp_` is reserved.

**Block direct file access.** Every PHP file opens with `defined( 'ABSPATH' ) || exit;`.

**Wrap every user-facing string** in a translation function with a literal text domain matching the plugin slug.

**Never modify core.** No editing WordPress files, no writing to `wp-config.php`, no altering other plugins' data.

**Clean up after yourself.** Deactivation clears scheduled events; uninstall removes options, meta, and tables.

## Code style

Follow [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/): tabs for indentation, spaces inside parentheses `function foo( $bar )`, Yoda conditions where the project uses them, snake_case functions, `Class_Name` classes, and full `<?php` tags. Match the surrounding file's existing style over the global default when they conflict.

## Red flags in review

- `add_action( 'wp_ajax_nopriv_...' )` on anything that writes
- `'permission_callback' => '__return_true'` on a writing route
- `update_option( $_POST['name'], $_POST['value'] )` — instant site takeover
- user-controlled `role`, `ID`, or `wp_capabilities` reaching `wp_insert_user()` / `update_user_meta()`
- `unserialize( $_` anything
- `$wpdb->query( "... $var ..." )`
- `echo $` with no escaping function
- `unlink()` / `include` with a request-derived path
- `base64_decode` + `eval`, nested decoders, long encoded blobs — see `references/backdoor-indicators.md`
- `register_post_type()` on `init` without flushing rewrite rules on activation
- `wp_schedule_event()` without a `wp_next_scheduled()` guard — duplicate events
- Enqueuing on every page instead of conditionally
- Direct `$wpdb` query where a core API (`WP_Query`, `get_posts`, `get_option`) exists
