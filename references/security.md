# Security

The three gates, then input handling, then output handling, then the eight vulnerability classes.

```
Gate 1  AUTHENTICATION  Is this a logged-in user?      is_user_logged_in()
Gate 2  AUTHORIZATION   May THIS user do THIS thing?   current_user_can( 'cap' )
Gate 3  INTENT          Did they mean to, right now?   check_admin_referer()
```

A nonce without a capability check is not security. A capability check without a nonce is CSRF-able. You need both, plus sanitization on input and escaping on output.

---

# Part 1 — Sanitization, Validation, and Escaping

Three distinct operations. Doing one does not excuse skipping the others.

- **Validate** — reject data that is the wrong shape. Do this first; rejecting is safer than cleaning.
- **Sanitize** — clean data on the way *in*, before storing or processing.
- **Escape** — make data safe on the way *out*, at the moment of printing, chosen by output context.

## Sanitization functions by data type

| Function | Use for |
|----------|---------|
| `sanitize_text_field()` | Single-line plain text — names, titles, keys. Strips tags, invalid UTF-8, extra whitespace |
| `sanitize_textarea_field()` | Multi-line plain text; preserves newlines |
| `sanitize_email()` | Email addresses (pair with `is_email()` to validate) |
| `sanitize_url()` / `esc_url_raw()` | URLs for storage or a request (not for display) |
| `sanitize_file_name()` | File names |
| `sanitize_key()` | Lowercase alphanumeric keys, option names, slugs, array keys |
| `sanitize_title()` | Post slug form of a string |
| `sanitize_user()` | Usernames |
| `sanitize_html_class()` | CSS class names |
| `sanitize_hex_color()` | `#rrggbb` color values |
| `sanitize_mime_type()` | MIME type strings |
| `sanitize_option()` | Values for a known option name |
| `sanitize_meta()` | Meta values for a registered meta key |
| `sanitize_term()` / `sanitize_term_field()` | Taxonomy terms |
| `sanitize_sql_orderby()` | ORDER BY clauses — still prefer an allowlist |
| `absint()` | Non-negative integers (IDs, counts) |
| `intval()` / `(int)` | Integers that may be negative |
| `floatval()` | Floats |
| `boolval()` / `! empty()` | Booleans / checkboxes |
| `wp_kses_post()` | Rich text that should keep post-level HTML |
| `wp_kses( $str, $allowed )` | Rich text with an explicit tag/attribute allowlist |

### Validation helpers

`is_email()`, `is_numeric()`, `is_array()`, `wp_http_validate_url()`, `in_array( $v, $allowed, true )`, `preg_match()` against an anchored pattern, `array_key_exists()`, `checkdate()`, `wp_is_uuid()`, `username_exists()`, `term_exists()`, `get_post()` returning non-null.

Prefer validating against an allowlist over sanitizing toward one — if a value should be one of three things, compare it to those three things.

### `wp_unslash()` — always

WordPress adds slashes to `$_GET`, `$_POST`, `$_REQUEST`, `$_COOKIE`, and `$_SERVER`. Unslash **before** sanitizing:

```php
$title = sanitize_text_field( wp_unslash( $_POST['title'] ?? '' ) );
```

Order matters: `wp_unslash()` then sanitize. Reversing it can leave stray backslashes or undo the sanitizer's work.

### Arrays

Sanitize recursively — a sanitizer applied to an array returns an empty string.

```php
$ids  = array_map( 'absint', (array) wp_unslash( $_POST['ids'] ?? array() ) );
$tags = array_map( 'sanitize_text_field', (array) wp_unslash( $_POST['tags'] ?? array() ) );

// Nested structures
function myplugin_sanitize_deep( $value ) {
    if ( is_array( $value ) ) {
        return array_map( 'myplugin_sanitize_deep', $value );
    }
    return sanitize_text_field( $value );
}
```

Also validate array *keys* — `sanitize_key()` each key, or allowlist them, before using them as option names, meta keys, or column names.

## Escaping functions by output context

| Context | Function | Example |
|---------|----------|---------|
| Inside an HTML element | `esc_html()` | `<p><?php echo esc_html( $t ); ?></p>` |
| Inside an HTML attribute | `esc_attr()` | `<div title="<?php echo esc_attr( $t ); ?>">` |
| `href` / `src` / any URL | `esc_url()` | `<a href="<?php echo esc_url( $u ); ?>">` |
| Inside `<textarea>` | `esc_textarea()` | `<textarea><?php echo esc_textarea( $t ); ?></textarea>` |
| Inline JavaScript string | `esc_js()` | `var x = '<?php echo esc_js( $t ); ?>';` |
| Data to JS (preferred) | `wp_json_encode()` | `var d = <?php echo wp_json_encode( $data ); ?>;` |
| XML | `esc_xml()` | |
| HTML that must survive | `wp_kses_post()` | `<?php echo wp_kses_post( $content ); ?>` |
| HTML, explicit allowlist | `wp_kses( $s, $allowed )` | |
| Translated string in HTML | `esc_html__()` / `esc_html_e()` | |
| Translated string in attribute | `esc_attr__()` / `esc_attr_e()` | |

### Critical distinctions

**`esc_url()` vs `esc_attr()` on `href`.** `esc_attr()` does not strip `javascript:` — a URL escaped only with `esc_attr()` in an `href` is still XSS. Use `esc_url()` for display, `esc_url_raw()`/`sanitize_url()` for storage or requests.

**`esc_js()` is narrow.** It is for a value inside a single-quoted inline JS string, nothing else. For structured data use `wp_json_encode()`, or better, `wp_localize_script()` / `wp_add_inline_script()`.

**Attributes must be quoted.** `<div class=<?php echo esc_attr( $x ); ?>>` is exploitable despite the escaping — an unquoted attribute lets a space start a new attribute. Always quote.

**Escape inside `printf`, not before.**

```php
printf(
    '<a href="%s" class="%s">%s</a>',
    esc_url( $url ),
    esc_attr( $class ),
    esc_html( $label )
);
```

**Translations are not safe.** `_e()` and `__()` output raw. Use `esc_html_e()` / `esc_html__()`. For translations containing markup, use `wp_kses()` with an allowlist around the translated string.

**Escape everything, including your own data.** Options, post meta, and database values may have been written before your sanitizer existed, by an older version, by another plugin, or by a different code path. Escape at output unconditionally.

### `wp_kses` with an allowlist

```php
$allowed = array(
    'a'      => array( 'href' => array(), 'title' => array(), 'target' => array() ),
    'strong' => array(),
    'em'     => array(),
    'br'     => array(),
    'ul'     => array(),
    'li'     => array(),
);
echo wp_kses( $content, $allowed );
```

`wp_kses_post()` allows everything permitted in post content — generous. Use an explicit allowlist when the content does not need that breadth. Never add `script`, `iframe`, `object`, `embed`, `form`, or `on*` event attributes to an allowlist.

## Complete example

```php
add_action( 'admin_post_myplugin_save_profile', 'myplugin_save_profile' );

function myplugin_save_profile() {
    // Gate 1+2: authentication and authorization
    if ( ! current_user_can( 'edit_users' ) ) {
        wp_die( esc_html__( 'Forbidden', 'myplugin' ), 403 );
    }

    // Gate 3: intent
    check_admin_referer( 'myplugin_save_profile', 'myplugin_nonce' );

    // Validate
    $user_id = absint( $_POST['user_id'] ?? 0 );
    if ( ! $user_id || ! get_userdata( $user_id ) ) {
        wp_die( esc_html__( 'Invalid user', 'myplugin' ), 400 );
    }

    $email = sanitize_email( wp_unslash( $_POST['email'] ?? '' ) );
    if ( ! is_email( $email ) ) {
        wp_die( esc_html__( 'Invalid email', 'myplugin' ), 400 );
    }

    // Sanitize the rest
    $display = sanitize_text_field( wp_unslash( $_POST['display_name'] ?? '' ) );
    $bio     = wp_kses_post( wp_unslash( $_POST['bio'] ?? '' ) );
    $site    = esc_url_raw( wp_unslash( $_POST['url'] ?? '' ) );
    $age     = absint( $_POST['age'] ?? 0 );

    // Allowlist rather than sanitize a constrained value
    $themes = array( 'light', 'dark', 'auto' );
    $theme  = in_array( $_POST['theme'] ?? '', $themes, true ) ? $_POST['theme'] : 'light';

    update_user_meta( $user_id, 'myplugin_bio', $bio );
    update_user_meta( $user_id, 'myplugin_theme', $theme );
    // Note: no user-controlled role or capability keys anywhere

    wp_safe_redirect( admin_url( 'users.php' ) );
    exit;
}
```

Rendering it back — escape per context, at output:

```php
<input type="email" name="email"
       value="<?php echo esc_attr( get_user_meta( $user_id, 'myplugin_email', true ) ); ?>">

<div class="bio"><?php echo wp_kses_post( get_user_meta( $user_id, 'myplugin_bio', true ) ); ?></div>

<a href="<?php echo esc_url( get_user_meta( $user_id, 'myplugin_url', true ) ); ?>">
    <?php echo esc_html( get_user_meta( $user_id, 'myplugin_display', true ) ); ?>
</a>
```

---

# Part 2 — The Eight Vulnerability Classes

Each: how it happens, vulnerable code, fixed code.


## 1. Broken Access Control / Privilege Escalation

The most common and most severe class. A state-changing handler runs without verifying the caller is allowed to invoke it.

### 1a. Missing capability check

```php
// VULNERABLE — any logged-in subscriber can change site settings
add_action( 'wp_ajax_myplugin_save', 'myplugin_save' );
function myplugin_save() {
    update_option( 'myplugin_settings', $_POST['settings'] );
    wp_send_json_success();
}
```

```php
// FIXED
add_action( 'wp_ajax_myplugin_save', 'myplugin_save' );
function myplugin_save() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_send_json_error( 'Forbidden', 403 );
    }
    check_ajax_referer( 'myplugin_save', 'nonce' );

    update_option( 'myplugin_settings', sanitize_text_field( wp_unslash( $_POST['settings'] ) ) );
    wp_send_json_success();
}
```

### 1b. Unauthenticated handler that should not be public

```php
// VULNERABLE — nopriv means anyone on the internet, no login required
add_action( 'wp_ajax_nopriv_myplugin_import', 'myplugin_import' );
```

Register the `nopriv` variant **only** for actions genuinely intended for logged-out visitors, and even then gate them (rate limit, validate, never allow writes to privileged data).

### 1c. Role check instead of capability check

```php
// VULNERABLE — roles are mutable and not the authority on permissions
if ( in_array( 'administrator', wp_get_current_user()->roles, true ) ) { ... }
if ( current_user_can( 'administrator' ) ) { ... }   // also wrong: role used as capability
```

```php
// FIXED — ask about the capability the action actually requires
if ( current_user_can( 'manage_options' ) ) { ... }
```

### 1d. Arbitrary option update — instant full takeover

```php
// VULNERABLE — attacker sets users_can_register=1 and default_role=administrator,
// registers, and owns the site.
update_option( $_POST['option_name'], $_POST['option_value'] );
```

```php
// FIXED — allowlist exactly which options this handler may touch
$allowed = array( 'myplugin_color', 'myplugin_layout' );
$name    = sanitize_key( $_POST['option_name'] ?? '' );
if ( ! in_array( $name, $allowed, true ) ) {
    wp_die( 'Invalid option', 400 );
}
update_option( $name, sanitize_text_field( wp_unslash( $_POST['option_value'] ) ) );
```

### 1e. User meta privilege escalation

`wp_capabilities`, `wp_user_level`, and `{$wpdb->prefix}capabilities` are role storage. Letting a user write arbitrary meta keys — via registration, profile update, or an import routine — is privilege escalation.

```php
// VULNERABLE — user controls which meta keys get written
foreach ( $_POST['meta'] as $key => $value ) {
    update_user_meta( $user_id, $key, $value );
}
```

```php
// FIXED — allowlist the keys, and never accept role/capability keys from input
$allowed = array( 'myplugin_phone', 'myplugin_company' );
foreach ( (array) $_POST['meta'] as $key => $value ) {
    $key = sanitize_key( $key );
    if ( in_array( $key, $allowed, true ) ) {
        update_user_meta( $user_id, $key, sanitize_text_field( wp_unslash( $value ) ) );
    }
}
```

The same applies to `wp_insert_user()` / `wp_update_user()`: never pass a user-supplied `role` or `ID`. A user-supplied `ID` turns a "create user" call into "overwrite an existing user, including the administrator."

### 1f. IDOR — missing ownership check

```php
// VULNERABLE — capability check passes, but any author can edit any other author's item
if ( current_user_can( 'edit_posts' ) ) {
    myplugin_update_item( absint( $_POST['item_id'] ), $data );
}
```

```php
// FIXED — verify this user owns this specific object
$item_id = absint( $_POST['item_id'] );
if ( ! current_user_can( 'edit_post', $item_id ) ) {   // meta-cap form, object-aware
    wp_die( 'Forbidden', 403 );
}
```

Prefer the object-aware meta capabilities: `edit_post`, `delete_post`, `edit_user`, `edit_term` with the object ID as the second argument.

---

## 2. Cross-Site Scripting (XSS)

Data reaches the page without escaping appropriate to where it lands. Stored XSS in an admin screen is the usual path to a rogue administrator account.

```php
// VULNERABLE
echo '<div class="wrap"><h1>' . get_option( 'myplugin_title' ) . '</h1>';
echo '<input type="text" value="' . $_GET['q'] . '">';
echo '<a href="' . $user_url . '">Link</a>';
```

```php
// FIXED — escaping function chosen by output context
echo '<div class="wrap"><h1>' . esc_html( get_option( 'myplugin_title' ) ) . '</h1>';
printf( '<input type="text" value="%s">', esc_attr( wp_unslash( $_GET['q'] ?? '' ) ) );
printf( '<a href="%s">Link</a>', esc_url( $user_url ) );
```

Key points:

- **Escape late** — at the print statement, not at assignment.
- **Context decides the function.** `esc_html()` inside an element, `esc_attr()` inside an attribute, `esc_url()` for `href`/`src`, `esc_textarea()` inside `<textarea>`, `esc_js()` for inline JS strings, `wp_kses_post()` when HTML must survive.
- **`esc_url()` on `href` is not optional** — it strips `javascript:` and `data:` schemes that `esc_attr()` leaves intact.
- **Shortcode attributes are user input.** They are one of the most common stored-XSS sources; escape every attribute at output.
- **Sanitizing on input does not remove the need to escape on output.** Data may have been stored before your sanitizer existed, or written by another code path.
- `_e()` / `__()` output is not escaped — use `esc_html_e()` / `esc_html__()` / `esc_attr_e()`.
- Never build attributes from unescaped data — an unquoted attribute allows breaking out without any `<`.

---

## 3. Cross-Site Request Forgery (CSRF)

A state-changing request that carries no proof of intent. An admin merely visiting an attacker's page triggers it with their session.

```php
// VULNERABLE — visiting a crafted URL/page performs the action as the admin
add_action( 'admin_post_myplugin_delete', 'myplugin_delete' );
function myplugin_delete() {
    if ( current_user_can( 'manage_options' ) ) {
        myplugin_delete_item( absint( $_GET['id'] ) );
    }
}
```

```php
// FIXED — form side
wp_nonce_field( 'myplugin_delete_' . $id, 'myplugin_nonce' );

// FIXED — handler side
add_action( 'admin_post_myplugin_delete', 'myplugin_delete' );
function myplugin_delete() {
    $id = absint( $_GET['id'] ?? 0 );

    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( 'Forbidden', 403 );
    }
    check_admin_referer( 'myplugin_delete_' . $id, 'myplugin_nonce' );

    myplugin_delete_item( $id );
    wp_safe_redirect( admin_url( 'admin.php?page=myplugin' ) );
    exit;
}
```

Which function where:

| Context | Verify with |
|---------|-------------|
| Admin form / `admin_post_*` | `check_admin_referer( $action, $name )` — dies on failure |
| AJAX (`wp_ajax_*`) | `check_ajax_referer( $action, $name )` — dies on failure |
| REST API | `wp_verify_nonce( $nonce, 'wp_rest' )`, or rely on cookie auth + a real `permission_callback` |
| Manual/conditional | `wp_verify_nonce()` — **returns** a value; you must check it |

`wp_verify_nonce()` returning falsy must be handled explicitly — calling it and ignoring the result is the same as having no nonce at all.

Nonces are tied to the user session, so they are not a substitute for a capability check; they are also not secret and must not be used as access tokens.

---

## 4. SQL Injection

```php
// VULNERABLE — direct interpolation
$results = $wpdb->get_results( "SELECT * FROM {$wpdb->prefix}mytable WHERE id = " . $_GET['id'] );

// VULNERABLE — interpolating into prepare()'s query argument defeats it entirely
$results = $wpdb->get_results( $wpdb->prepare( "SELECT * FROM t WHERE id = $id" ) );

// VULNERABLE — esc_sql() only escapes quoted strings; ORDER BY is unquoted
$order = esc_sql( $_GET['order'] );
$results = $wpdb->get_results( "SELECT * FROM t ORDER BY $order" );
```

```php
// FIXED — placeholders, values passed separately
$results = $wpdb->get_results(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->prefix}mytable WHERE id = %d AND status = %s",
        absint( $_GET['id'] ),
        sanitize_key( $_GET['status'] )
    )
);

// FIXED — identifiers cannot be placeholders; allowlist them
$allowed_cols = array( 'name', 'created_at' );
$orderby = in_array( $_GET['orderby'] ?? '', $allowed_cols, true ) ? $_GET['orderby'] : 'name';
$order   = ( strtoupper( $_GET['order'] ?? '' ) === 'DESC' ) ? 'DESC' : 'ASC';
$results = $wpdb->get_results( "SELECT * FROM {$wpdb->prefix}mytable ORDER BY `{$orderby}` {$order}" );

// FIXED — IN() clause with a dynamic number of placeholders
$ids          = array_map( 'absint', (array) $_POST['ids'] );
$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );
$results      = $wpdb->get_results(
    $wpdb->prepare( "SELECT * FROM {$wpdb->prefix}mytable WHERE id IN ($placeholders)", $ids )
);
```

Rules:

- `%d` integers, `%f` floats, `%s` strings. Do **not** wrap `%s` in quotes yourself — `prepare()` adds them.
- `$wpdb->prefix` and table names are safe to interpolate; **user input never is**.
- Table and column names cannot be placeholders — allowlist them against a fixed array.
- `LIKE` needs `$wpdb->esc_like()` before the value goes into `%s`:
  `$wpdb->prepare( "... LIKE %s", '%' . $wpdb->esc_like( $term ) . '%' )`
- `$wpdb->insert()`, `->update()`, `->delete()`, `->replace()` prepare internally when given a format array — prefer them for simple writes.
- Also audit `WP_Query` / `get_posts()` arguments: `meta_query` values, `orderby`, and anything reaching the `posts_where` filter.

---

## 5. Arbitrary File Upload / Read / Delete / Inclusion

### 5a. Upload

```php
// VULNERABLE — attacker uploads shell.php and browses to it: full RCE
move_uploaded_file( $_FILES['file']['tmp_name'], WP_CONTENT_DIR . '/uploads/' . $_FILES['file']['name'] );
```

```php
// FIXED
if ( ! current_user_can( 'upload_files' ) ) {
    wp_die( 'Forbidden', 403 );
}
check_admin_referer( 'myplugin_upload', 'myplugin_nonce' );

require_once ABSPATH . 'wp-admin/includes/file.php';

$allowed = array( 'jpg|jpeg' => 'image/jpeg', 'png' => 'image/png', 'pdf' => 'application/pdf' );

$checked = wp_check_filetype_and_ext(
    $_FILES['file']['tmp_name'],
    sanitize_file_name( $_FILES['file']['name'] ),
    $allowed
);
if ( ! $checked['ext'] || ! $checked['type'] ) {
    wp_die( 'Disallowed file type', 400 );
}

$result = wp_handle_upload( $_FILES['file'], array( 'test_form' => false, 'mimes' => $allowed ) );
if ( isset( $result['error'] ) ) {
    wp_die( esc_html( $result['error'] ), 400 );
}
```

Never trust `$_FILES['file']['type']` — it is attacker-controlled. `wp_check_filetype_and_ext()` inspects real content. Watch for double extensions (`shell.php.jpg`), null bytes, `.phtml` / `.php5` / `.phar` / `.htaccess`, and SVG (which can carry script). Store uploads under `wp_upload_dir()` and, for non-public files, outside the webroot or behind a deny rule.

### 5b. Path traversal on read/delete

```php
// VULNERABLE — ../../../wp-config.php
$file = WP_CONTENT_DIR . '/myplugin/' . $_GET['file'];
echo file_get_contents( $file );
unlink( $file );
```

```php
// FIXED — resolve, then verify containment
$base = realpath( WP_CONTENT_DIR . '/myplugin' );
$path = realpath( $base . '/' . wp_basename( $_GET['file'] ?? '' ) );

if ( false === $path || 0 !== strpos( $path, $base . DIRECTORY_SEPARATOR ) ) {
    wp_die( 'Invalid path', 400 );
}
```

`wp_basename()` strips directory components; `realpath()` + prefix check defeats symlinks and encoded traversal. Better still: store an ID in the database and map it to a path server-side, so the path never comes from the request.

### 5c. Local file inclusion

```php
// VULNERABLE
include MYPLUGIN_DIR . 'views/' . $_GET['view'] . '.php';
```

```php
// FIXED — allowlist, never build a path from input
$views = array( 'settings' => 'settings.php', 'about' => 'about.php' );
$key   = sanitize_key( $_GET['view'] ?? 'settings' );
if ( isset( $views[ $key ] ) ) {
    include MYPLUGIN_DIR . 'views/' . $views[ $key ];
}
```

---

## 6. PHP Object Injection (Insecure Deserialization)

`unserialize()` on attacker input instantiates arbitrary classes and fires magic methods (`__wakeup`, `__destruct`, `__toString`). Chained through gadget classes present in WordPress core, a plugin, or a Composer dependency, this reaches RCE or file deletion.

```php
// VULNERABLE
$data = unserialize( $_POST['data'] );
$data = unserialize( base64_decode( $_COOKIE['prefs'] ) );

// VULNERABLE — maybe_unserialize() auto-unserializes anything that looks serialized
$data = maybe_unserialize( get_post_meta( $id, 'key', true ) );   // if that meta came from a user
```

```php
// FIXED — use JSON for untrusted data
$data = json_decode( wp_unslash( $_POST['data'] ), true );
if ( ! is_array( $data ) ) {
    wp_die( 'Invalid payload', 400 );
}

// If serialization is genuinely unavoidable (PHP 7+)
$data = unserialize( $raw, array( 'allowed_classes' => false ) );
```

Note that `update_option()` / `update_post_meta()` serialize arrays automatically and `get_option()` unserializes on read. That is safe for values *you* control — the danger is storing an attacker-supplied serialized string and later reading it back through `maybe_unserialize()`.

---

## 7. SSRF and Open Redirect

### 7a. SSRF

```php
// VULNERABLE — reaches cloud metadata endpoints, internal services, localhost
$response = wp_remote_get( $_POST['url'] );
```

```php
// FIXED
$url = esc_url_raw( wp_unslash( $_POST['url'] ?? '' ) );

if ( ! wp_http_validate_url( $url ) ) {
    wp_die( 'Invalid URL', 400 );
}

$response = wp_safe_remote_get(
    $url,
    array(
        'timeout'            => 10,
        'redirection'        => 0,      // redirects can bypass the validation
        'reject_unsafe_urls' => true,
    )
);
```

`wp_safe_remote_*()` blocks loopback, private, and reserved IP ranges and restricts ports to 80/443/8080. It does **not** reliably re-validate redirect targets, so set `redirection => 0` unless you have a reason not to. Stronger still: allowlist the hosts your plugin is permitted to contact.

### 7b. Open redirect

```php
// VULNERABLE — redirects to any attacker domain, powers phishing and SSRF bypasses
wp_redirect( $_GET['redirect_to'] );
```

```php
// FIXED — wp_safe_redirect() restricts to the site's own host
wp_safe_redirect( $_GET['redirect_to'] ?? admin_url() );
exit;
```

Always `exit;` after a redirect — without it, execution continues and the code below still runs.

---

## 8. Sensitive Data Exposure

- Log files in `wp-content/` or the plugin directory are reachable over HTTP. Never write logs there; never log credentials, tokens, or full request bodies.
- Do not ship API keys, license secrets, or private endpoints hardcoded in plugin files — plugin source is public.
- Store third-party credentials in options; consider `wp-config.php` constants for high-value secrets, and never echo them back into a settings field in plaintext.
- Do not expose full server paths in error output. Guard debug output with `WP_DEBUG` and never `display_errors` in production.
- Add a blank `index.php` to every plugin subdirectory as defense in depth against directory listing.
- Do not expose user emails, hashes, or private post data via REST or AJAX responses without a capability check on the reader.
- Avoid timing-unsafe comparisons for tokens; use `hash_equals()` for secret comparison.

---

# Part 3 — Patterns From Recent Incidents (2026)

The eight classes above name *what* goes wrong. These are the specific *developer mistakes* behind the most severe plugin CVEs of 2026 — each sat in a plugin with hundreds of thousands to millions of installs, and each was exploitable without logging in.

Context that should change how urgently you treat any finding: in 2025 there were **11,334** new WordPress ecosystem vulnerabilities (+42% year over year), **91%** in plugins; **46%** had no patch at disclosure; **broken access control was the most exploited class**; and the **median time from disclosure to mass exploitation was 5 hours**. There is no "patch it next sprint" for a critical plugin bug.

## A. Homemade "safe unserialize" helpers

Two separate 2026 critical RCEs (a donation plugin, CVSS 10.0; an events plugin, CVSS 9.8) had a helper that *checked* serialized data for objects and then unserialized it. Both checks were bypassable: malformed trailing data made the pre-check `unserialize()` return `false`, the helper concluded "no objects present", and the real deserialization then started restoring objects — firing magic methods — before failing.

```php
// VULNERABLE — every variant of "inspect, then unserialize" races the parser
function myplugin_is_safe( $data ) {
    $probe = @unserialize( $data );                  // returns false on malformed input…
    return ! myplugin_contains_object( $probe );     // …so this says "safe"
}
if ( myplugin_is_safe( $raw ) ) {
    $value = unserialize( $raw );                    // objects instantiated here
}

// Also VULNERABLE — regex filters for "O:" are bypassed ("C:", nesting, whitespace)
if ( ! preg_match( '/O:\d+:/', $raw ) ) { $value = unserialize( $raw ); }
```

```php
// FIXED — let PHP enforce it, or don't deserialize at all
$value = json_decode( $raw, true );                                   // preferred
$value = unserialize( $raw, array( 'allowed_classes' => false ) );    // if you must
```

**Rule:** there is no safe way to *inspect* attacker-controlled serialized data before unserializing it. Only `allowed_classes => false`, or not using `unserialize()`, is safe. Treat any helper named `*safe*unserialize*`, `is_safe_*`, or `contains_object` as a red flag.

## B. `is_callable()` is not an allowlist

An events plugin let template attributes flow through `extract()` into a variable that was later called if `is_callable()` returned true. An attacker supplied `wp_update_user` as the "callable" with their own arguments, reset the administrator's password, logged in, and uploaded a plugin.

```php
// VULNERABLE — is_callable() only proves the function EXISTS
extract( $attributes );                      // attacker now controls $callback, $classes, …
if ( is_callable( $callback ) ) {
    $result = call_user_func( $callback, $value );
}
```

```php
// FIXED — map input to a fixed set of known callbacks; never extract() untrusted data
$formatters = array(
    'upper' => 'strtoupper',
    'title' => 'ucwords',
);
$key = sanitize_key( $attributes['format'] ?? '' );
if ( isset( $formatters[ $key ] ) ) {
    $result = call_user_func( $formatters[ $key ], $value );
}
```

Any value that becomes a function name, method name, class name, hook name, or `array_map()` callback must come from a hardcoded map — never from data.

## C. Untrusted content reaching block and shortcode parsers

The same events plugin passed its whole template — **including comments, and including *unapproved* comments shown through WordPress's moderation-preview link** — to `do_blocks()`. A comment box became a way to feed arbitrary block attributes to server-side render callbacks.

```php
// VULNERABLE
echo do_blocks( $template_html . $comments_html );
echo do_shortcode( $comment->comment_content );
echo apply_filters( 'the_content', get_comment_text() );   // runs do_blocks + do_shortcode
```

```php
// FIXED — parse only content written by someone with the right capability;
// render user-submitted text as text
echo do_blocks( $template_html );
echo wp_kses_post( wpautop( $comment->comment_content ) );
```

Comments, form submissions, reviews, and any front-end user content must never reach `do_blocks()`, `do_shortcode()`, `parse_blocks()`, or `apply_filters( 'the_content' )`. "Pending moderation" is not "safe" — the submitter can preview a pending comment, so its content still renders.

## D. Second-order SQL injection

A backup/migration plugin on 3M+ sites (CVSS 8.8) stored attacker text that arrived through a public channel (trackbacks), then later — during a restore that rewrote URLs and table prefixes — concatenated that stored text into SQL. A trailing backslash broke out of the string. The injection leaked a restore secret, which unlocked importing an archive containing a **must-use plugin**: RCE on the next page load.

```php
// VULNERABLE — "it came from our own database" is not a trust boundary
$old = get_option( 'myplugin_old_url' );
$wpdb->query( "UPDATE {$table} SET content = REPLACE(content, '{$old}', '{$new}') WHERE id = {$row->id}" );
```

```php
// FIXED — prepare EVERY query: imports, migrations, cron, stored values included
$wpdb->query( $wpdb->prepare(
    "UPDATE {$table} SET content = REPLACE(content, %s, %s) WHERE id = %d",
    $old, $new, $row->id
) );
```

Data in your own tables was written by someone — often anonymously (comments, trackbacks, form entries, order notes). Every query uses `prepare()` regardless of where the value came from. Table names built at runtime (prefix rewrites during restore) must match `/^[A-Za-z0-9_]+$/` before interpolation.

## E. Import, restore, and "upload a package" features are code execution

That chain ended by writing a file into `wp-content/mu-plugins/`. Any feature that unpacks an archive, restores a backup, or imports settings can put PHP somewhere WordPress will run it.

- Require `manage_options` (or `install_plugins` if it can write code) **and** a nonce — never a secret key alone.
- Validate every archive entry with `realpath()` containment *before* extracting; reject `..`, absolute paths, and symlinks.
- Never extract into `WP_PLUGIN_DIR`, `WPMU_PLUGIN_DIR`, a theme directory, or the webroot.
- Reject executable extensions (`php`, `phtml`, `phar`, `.htaccess`) unless installing code is the feature's explicit purpose — in which case require `install_plugins`.
- Use `unzip_file()` / `WP_Filesystem` rather than `ZipArchive::extractTo()` on an unvalidated archive.

## F. Leaking tokens in responses

A translation plugin (CVSS 9.8) exposed the **plaintext password-reset key** in a response under certain conditions — enough to take over the administrator account with no other bug. The migration plugin lost its restore secret the same way, through a REST response.

- Never put `get_password_reset_key()` output, activation keys, restore keys, API secrets, or another user's nonce in any response, redirect URL, log line, or error message.
- Audit what your REST/AJAX responses serialize: returning a whole `WP_User`, options array, or settings object often includes secrets.
- Compare secrets with `hash_equals()`; store tokens hashed, as core does for reset keys.
- Keys guarding dangerous operations must be single-use and expiring.

## G. Trusting external identity (SSO, OAuth, magic links)

A site-management plugin (CVSS 9.8) had an SSO flow that could be driven to log an unauthenticated visitor in as an administrator.

When a plugin accepts identity from elsewhere — SSO, OAuth callbacks, "log in with…", magic links, signed URLs from a SaaS dashboard — verify all of these before calling `wp_set_auth_cookie()`:

- **Signature** — verified with the provider's key, constant-time; algorithm fixed server-side, never read from the token.
- **Expiry and issue time** — short-lived; reject stale tokens.
- **Audience / site binding** — minted *for this site*.
- **Single use** — store and reject replayed token IDs and `state` values.
- **User mapping** — the WordPress user comes from your verified mapping, never from a `user_id` or `email` the request supplies.

```php
// VULNERABLE — the request chooses who to become
$user_id = absint( $_GET['uid'] );
if ( myplugin_token_looks_valid( $_GET['token'] ) ) {
    wp_set_auth_cookie( $user_id );
}
```

Any code path ending in `wp_set_auth_cookie()`, `wp_set_current_user()`, or `wp_signon()` deserves the same scrutiny as the login form itself.

## H. Contributors are attackers too

WordPress 7.1.1 (September 2026) fixed eleven core issues; several were authorization gaps reachable by a **contributor** or any logged-in user: overwriting others' posts, discovering draft slugs through REST, reparenting comments, and a missing `read_post` check leaking a private post's title. Plugins repeat these mistakes constantly.

- Check the **object**, not just the capability: `current_user_can( 'edit_post', $id )`, `current_user_can( 'read_post', $id )`.
- Responses that include related objects (parent post, attached post, author) need a `read_post` check on *each* related object.
- Anything that changes an object's relationships — parent, author, terms, owner — needs an edit check on **both** the object and the new target.
