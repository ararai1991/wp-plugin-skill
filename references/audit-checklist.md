# Plugin Security Audit Checklist

Ordered by how often each finding turns into a real CVE. Work top to bottom.

For every finding, answer these before assigning severity:

1. **Who can reach it?** Unauthenticated → critical. Subscriber → high. Admin-only → usually low (an admin already has that power).
2. **What does it do?** Writes/deletes/executes → higher than reads.
3. **Is it actually reachable?** Confirm the hook is registered and the code path is live.

---

## Phase 1 — Map the attack surface

Enumerate before you judge. Build the list of entry points first.

```bash
# All AJAX handlers — note which are nopriv
grep -rn "add_action( *['\"]wp_ajax" --include=*.php .

# REST routes and their permission callbacks
grep -rn -A5 "register_rest_route" --include=*.php .

# admin-post handlers
grep -rn "add_action( *['\"]admin_post" --include=*.php .

# Anything running on every request
grep -rn "add_action( *['\"]\(init\|template_redirect\|parse_request\|wp_loaded\)" --include=*.php .

# Shortcodes and blocks
grep -rn "add_shortcode\|register_block_type" --include=*.php .

# Direct-access guards — every PHP file should have one
grep -rLn "defined( *'ABSPATH'" --include=*.php .
```

---

## Phase 2 — Access control (highest yield)

- [ ] Every `wp_ajax_*` handler calls `current_user_can()` before any side effect
- [ ] Every `wp_ajax_nopriv_*` handler is intentionally public — and safe when no user is logged in
- [ ] Every `register_rest_route` has a `permission_callback` that is not `__return_true` on a writing route
- [ ] No permission check lives inside a route callback instead of its `permission_callback`
- [ ] Every `admin_post_*` handler checks capability
- [ ] Capabilities are used, never roles (`current_user_can( 'administrator' )` is a bug)
- [ ] Object-level ownership checked for per-object operations (`current_user_can( 'edit_post', $id )`)
- [ ] `update_option()` / `delete_option()` never take a user-controlled option *name*
- [ ] `update_user_meta()` / `add_user_meta()` never take a user-controlled meta *key*
- [ ] No user-controlled `role`, `ID`, or `wp_capabilities` reaching `wp_insert_user()` / `wp_update_user()`
- [ ] Registration/profile handlers cannot be used to assign a privileged role
- [ ] Menu-page capability arguments are not the only check — page callbacks check too

```bash
grep -rn "wp_ajax_nopriv" --include=*.php .
grep -rn "permission_callback.*__return_true" --include=*.php .
grep -rn "update_option( *\$" --include=*.php .
grep -rn "update_user_meta\|add_user_meta\|wp_insert_user\|wp_update_user\|set_role\|add_cap" --include=*.php .
grep -rn "current_user_can( *['\"]administrator" --include=*.php .
```

---

## Phase 3 — CSRF

- [ ] Every state-changing handler verifies a nonce
- [ ] `wp_verify_nonce()` results are actually checked (not called and discarded)
- [ ] Nonce action strings are specific, ideally including the object ID
- [ ] Forms emit `wp_nonce_field()`; links use `wp_nonce_url()`
- [ ] AJAX calls send the nonce and the handler calls `check_ajax_referer()`
- [ ] Nonces are not used as the only authorization mechanism

```bash
grep -rn "wp_verify_nonce" --include=*.php .          # each must be inside a conditional
grep -rn "check_admin_referer\|check_ajax_referer" --include=*.php .
```

---

## Phase 4 — Output escaping (XSS)

- [ ] Every `echo` / `print` / `printf` / `<?=` of a variable is escaped
- [ ] Escaping function matches output context (html / attr / url / textarea / js)
- [ ] `href` and `src` use `esc_url()`, not `esc_attr()`
- [ ] All HTML attributes are quoted
- [ ] Shortcode attributes are escaped at output
- [ ] `_e()` / `__()` replaced with `esc_html_e()` / `esc_html__()` where output is HTML
- [ ] Admin notices and settings-field rendering escape their values
- [ ] `wp_kses` allowlists contain no `script`, `iframe`, `on*`, `style` with expressions
- [ ] Data passed to JS uses `wp_json_encode()` / `wp_localize_script()`

```bash
grep -rn "echo \$\|print \$\|<?= *\$" --include=*.php .
grep -rn "echo.*\$_\(GET\|POST\|REQUEST\|SERVER\|COOKIE\)" --include=*.php .
grep -rn 'href="<?php echo \$\|href=.*esc_attr' --include=*.php .
```

---

## Phase 5 — SQL injection

- [ ] Every `$wpdb` call containing a variable uses `prepare()`
- [ ] No variable interpolated into `prepare()`'s first argument
- [ ] `%s` placeholders are not manually wrapped in quotes
- [ ] ORDER BY / column / table names come from an allowlist, not input
- [ ] `LIKE` values pass through `$wpdb->esc_like()`
- [ ] `IN()` clauses build placeholders dynamically, not by concatenating values
- [ ] `esc_sql()` is not the primary defense anywhere
- [ ] `WP_Query` `meta_query`, `orderby`, and `posts_where` filters are checked

```bash
grep -rn '\$wpdb->\(query\|get_results\|get_row\|get_var\|get_col\)' --include=*.php .
grep -rn 'prepare( *"[^"]*\$' --include=*.php .     # interpolation inside prepare's query
grep -rn "esc_sql" --include=*.php .
```

---

## Phase 6 — File operations

- [ ] Uploads go through `wp_handle_upload()` with a `mimes` allowlist
- [ ] `wp_check_filetype_and_ext()` validates real content, not `$_FILES[...]['type']`
- [ ] Executable extensions rejected: `php`, `phtml`, `php5`, `phar`, `htaccess`, `svg` (unless sanitized)
- [ ] No `move_uploaded_file()` straight to a user-supplied name
- [ ] Every `unlink` / `file_get_contents` / `fopen` / `include` path is validated with `realpath()` + prefix containment
- [ ] `wp_basename()` applied to any filename from a request
- [ ] No `include` / `require` with a request-derived variable path
- [ ] `WP_Filesystem` used for writes where appropriate
- [ ] Non-public uploads are outside the webroot or protected

```bash
grep -rn "move_uploaded_file\|\$_FILES" --include=*.php .
grep -rn "unlink\|file_get_contents\|file_put_contents\|fopen\|rmdir\|scandir\|readfile" --include=*.php .
grep -rn "include *\$\|require *\$\|include_once *\$\|require_once *\$" --include=*.php .
```

---

## Phase 7 — Deserialization and dangerous functions

- [ ] No `unserialize()` on any request-derived value
- [ ] `maybe_unserialize()` not applied to data that originated from user input
- [ ] No `eval`, `assert`, `create_function`, `preg_replace` with `/e`
- [ ] No `system`, `exec`, `shell_exec`, `passthru`, `popen`, `proc_open` with user input
- [ ] No `extract()` on request data
- [ ] No `call_user_func` / `call_user_func_array` with a user-supplied callback name
- [ ] No variable variables (`$$var`) driven by input

```bash
grep -rn "unserialize\|maybe_unserialize" --include=*.php .
grep -rn "\beval\b\|assert(\|create_function\|preg_replace( *['\"].*e['\"]" --include=*.php .
grep -rn "shell_exec\|passthru\|proc_open\|popen\|\bsystem(\|\bexec(" --include=*.php .
grep -rn "extract(\|call_user_func" --include=*.php .
```

---

## Phase 8 — SSRF, redirects, and external requests

- [ ] `wp_safe_remote_*()` used wherever the URL is influenced by input
- [ ] `redirection => 0` set, or redirect targets re-validated
- [ ] URL allowlist enforced for known third-party integrations
- [ ] `wp_safe_redirect()` used for any redirect target derived from input
- [ ] Every redirect is followed by `exit;`
- [ ] `sslverify` is not disabled
- [ ] Webhook signatures verified with `hash_equals()`

```bash
grep -rn "wp_remote_get\|wp_remote_post\|wp_remote_request\|curl_exec\|file_get_contents( *['\"]http" --include=*.php .
grep -rn "wp_redirect\|header( *['\"]Location" --include=*.php .
grep -rn "sslverify" --include=*.php .
```

---

## Phase 9 — Information exposure and secrets

- [ ] No API keys, tokens, or passwords hardcoded in source
- [ ] No log files written inside the webroot
- [ ] Secrets never written to logs or echoed into settings fields
- [ ] Error output does not leak full paths, queries, or stack traces in production
- [ ] Debug output guarded by `WP_DEBUG`
- [ ] `index.php` present in each subdirectory
- [ ] REST/AJAX responses do not include emails, hashes, or private data without a reader capability check
- [ ] Token comparisons use `hash_equals()`, not `==`

```bash
grep -rniE "(api[_-]?key|secret|passwd|password|token|bearer)['\"]? *[:=]" --include=*.php .
grep -rn "error_log\|var_dump\|print_r\|debug_backtrace" --include=*.php .
```

---

## Phase 10 — Supply chain and integrity

- [ ] `composer.json` / `package.json` dependencies reviewed and current
- [ ] Bundled third-party libraries are current and not known-vulnerable
- [ ] No obfuscated, minified, or unreadable PHP
- [ ] No remote code fetched and executed at runtime
- [ ] Auto-update mechanisms verify signatures over TLS
- [ ] See `backdoor-indicators.md` for the full pass

---

## Phase 11 — Tooling

Run these; they catch what grep misses:

```bash
# Official WordPress.org checks — Security category must pass for directory submission
wp plugin check <plugin-slug>

# WordPress Coding Standards, security sniffs
composer require --dev wp-coding-standards/wpcs
phpcs --standard=WordPress-Extra --extensions=php <plugin-dir>

# Static analysis
phpstan analyse --level=5 <plugin-dir>
psalm --taint-analysis          # taint tracking finds input→sink flows
```

Relevant PHPCS sniff groups: `WordPress.Security.EscapeOutput`, `WordPress.Security.ValidatedSanitizedInput`, `WordPress.Security.NonceVerification`, `WordPress.DB.PreparedSQL`, `WordPress.DB.DirectDatabaseQuery`.

Tooling supplements review; it does not replace it. Static analysis cannot tell whether a capability is the *right* capability for the action.

---

## Reporting template

```
[SEVERITY] Vulnerability class — file.php:line

Reachable by: unauthenticated | subscriber | contributor | admin
Entry point:  wp_ajax_nopriv_myplugin_import

Issue:
  <one or two sentences on the missing control>

Impact:
  <concrete outcome: rogue admin account, RCE, data disclosure>

Proof of concept:
  <the request that triggers it>

Fix:
  <the code change>
```

Severity guide: **Critical** — unauthenticated RCE, privilege escalation to admin, or arbitrary file write. **High** — low-privilege user reaching a privileged action, unauthenticated data disclosure, SQLi. **Medium** — CSRF, stored XSS needing a privileged author, authenticated SSRF. **Low** — admin-only self-XSS, information disclosure of low value.
