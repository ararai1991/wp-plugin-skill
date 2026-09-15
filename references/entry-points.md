# Entry Points and Their Required Gates

Every way an HTTP request reaches plugin code. Auditing a plugin means enumerating these first — a vulnerability in code no request can reach is theoretical; a missing check on an unauthenticated entry point is critical.

## Quick reference

| Entry point | Reachable by | Auth gate | Nonce gate |
|-------------|--------------|-----------|------------|
| `wp_ajax_{action}` | Any logged-in user (incl. subscriber) | `current_user_can()` | `check_ajax_referer()` |
| `wp_ajax_nopriv_{action}` | **Anyone, unauthenticated** | n/a — design as public | n/a (use other controls) |
| `register_rest_route` | Per `permission_callback` | In `permission_callback` | Cookie auth → `wp_rest` nonce |
| `admin_post_{action}` | Any logged-in user | `current_user_can()` | `check_admin_referer()` |
| `admin_post_nopriv_{action}` | **Anyone, unauthenticated** | n/a — design as public | n/a |
| `admin_init` / `admin_menu` | Any logged-in user hitting wp-admin | `current_user_can()` | If it writes: yes |
| Shortcodes | Anyone who can view the post | Escape output | n/a (read-only) |
| Blocks (`render_callback`) | Anyone viewing the page | Escape output | n/a |
| `init` / `template_redirect` / `parse_request` | **Anyone, every page load** | Gate explicitly | If it writes: yes |
| Custom query var / rewrite endpoint | **Anyone, unauthenticated** | Gate explicitly | If it writes: yes |
| Direct file access to a plugin PHP file | **Anyone** | `defined( 'ABSPATH' ) \|\| exit;` | n/a |
| Webhook receiver | **Anyone** | Signature verification | n/a |
| WP-Cron (`wp_schedule_event`) | Anyone can trigger `wp-cron.php` | Do not trust caller | n/a |
| `save_post` / `profile_update` etc. | Whoever triggered the core action | Re-check capability | Re-check nonce |

## AJAX

```php
// Logged-in only — still needs BOTH gates, "logged in" includes subscribers
add_action( 'wp_ajax_myplugin_action', 'myplugin_handler' );

function myplugin_handler() {
    if ( ! current_user_can( 'edit_posts' ) ) {
        wp_send_json_error( array( 'message' => 'Forbidden' ), 403 );
    }
    check_ajax_referer( 'myplugin_action', 'nonce' );

    $value = sanitize_text_field( wp_unslash( $_POST['value'] ?? '' ) );
    // ... do the work
    wp_send_json_success();
}
```

Nonce for the JS side:

```php
wp_localize_script( 'myplugin-js', 'myPluginData', array(
    'ajaxUrl' => admin_url( 'admin-ajax.php' ),
    'nonce'   => wp_create_nonce( 'myplugin_action' ),
) );
```

**The `nopriv` trap.** `add_action( 'wp_ajax_nopriv_x', ... )` makes the action callable by anyone with no session. Register it only when the action is genuinely for logged-out visitors. If both variants share one callback, the callback must handle the unauthenticated case safely — do not assume a user exists.

## REST API

```php
add_action( 'rest_api_init', function () {
    register_rest_route( 'myplugin/v1', '/items/(?P<id>\d+)', array(
        'methods'             => WP_REST_Server::EDITABLE,
        'callback'            => 'myplugin_update_item',
        'permission_callback' => function ( WP_REST_Request $request ) {
            return current_user_can( 'edit_post', (int) $request['id'] );
        },
        'args'                => array(
            'id'    => array(
                'required'          => true,
                'validate_callback' => static fn( $v ) => is_numeric( $v ) && $v > 0,
                'sanitize_callback' => 'absint',
            ),
            'title' => array(
                'required'          => true,
                'sanitize_callback' => 'sanitize_text_field',
            ),
        ),
    ) );
} );
```

Rules:

- `permission_callback` is **required** since WP 5.5. Omitting it produces a notice and the route is treated as unprotected.
- `'permission_callback' => '__return_true'` means fully public — correct only for genuinely public read-only data.
- Put the check **in** `permission_callback`, not in the route callback. WordPress relies on the permission callback for its CSRF handling of cookie-authenticated requests.
- Use `args` with `validate_callback` / `sanitize_callback` — validation at the schema layer is applied consistently.
- For cookie-authenticated JS, send the `wp_rest` nonce in the `X-WP-Nonce` header (`wp_create_nonce( 'wp_rest' )`).
- `WP_REST_Server::READABLE` still needs a permission callback if the data is not public.

## Admin forms

```php
// Rendering
<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
    <input type="hidden" name="action" value="myplugin_save">
    <?php wp_nonce_field( 'myplugin_save', 'myplugin_nonce' ); ?>
    <input type="text" name="title" value="<?php echo esc_attr( $title ); ?>">
    <?php submit_button(); ?>
</form>

// Handling
add_action( 'admin_post_myplugin_save', 'myplugin_save' );

function myplugin_save() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( esc_html__( 'Forbidden', 'myplugin' ), 403 );
    }
    check_admin_referer( 'myplugin_save', 'myplugin_nonce' );

    update_option( 'myplugin_title', sanitize_text_field( wp_unslash( $_POST['title'] ?? '' ) ) );

    wp_safe_redirect( add_query_arg( 'updated', '1', admin_url( 'admin.php?page=myplugin' ) ) );
    exit;
}
```

## Settings API

`register_setting()` with a `sanitize_callback` handles nonce and capability through `options.php` — but the sanitize callback is your responsibility:

```php
register_setting( 'myplugin_group', 'myplugin_options', array(
    'type'              => 'array',
    'sanitize_callback' => 'myplugin_sanitize_options',
    'default'           => array(),
) );

function myplugin_sanitize_options( $input ) {
    $output = array();
    $output['title']   = sanitize_text_field( $input['title'] ?? '' );
    $output['count']   = absint( $input['count'] ?? 0 );
    $output['enabled'] = ! empty( $input['enabled'] );
    $output['email']   = sanitize_email( $input['email'] ?? '' );
    return $output;   // never return $input unfiltered
}
```

`add_options_page()` and friends take a capability argument — that gates the *menu*, but the page callback should still check, since the callback can be reachable independently.

## Shortcodes

```php
function myplugin_shortcode( $atts, $content = '' ) {
    $atts = shortcode_atts( array( 'id' => 0, 'title' => '' ), $atts, 'myplugin' );

    // Attributes are user input — escape at output
    return sprintf(
        '<div class="myplugin" data-id="%d"><h3>%s</h3>%s</div>',
        absint( $atts['id'] ),
        esc_html( $atts['title'] ),
        wp_kses_post( $content )
    );
}
add_shortcode( 'myplugin', 'myplugin_shortcode' );
```

Shortcodes must **return**, not echo. Anyone who can author a post can supply attributes — contributors included — so unescaped attributes are a standard stored-XSS route.

## Hooks that fire on every request

`init`, `wp_loaded`, `template_redirect`, `parse_request`, `wp` — these run for every visitor including unauthenticated ones. Any code here that inspects `$_GET`/`$_POST` and acts on it is an unauthenticated entry point:

```php
// VULNERABLE — a public, unauthenticated, unprotected action
add_action( 'init', function () {
    if ( isset( $_GET['myplugin_reset'] ) ) {
        myplugin_reset_all_settings();
    }
} );
```

## WP-Cron

`wp-cron.php` is publicly reachable, so a cron callback can be triggered by an outsider at will. Cron callbacks must not trust the caller, must be idempotent, and must not read request data.

## Webhooks

An endpoint receiving third-party callbacks is unauthenticated by nature. Verify the provider's signature with `hash_equals()` against the raw request body before parsing, and never rely on an IP allowlist alone.

## Direct file access

Every PHP file in the plugin must start with:

```php
defined( 'ABSPATH' ) || exit;
```

Without it, a file that assumes WordPress is loaded can be requested directly — the classic source of unauthenticated file-handler CVEs.

## Core action hooks

Callbacks on `save_post`, `profile_update`, `user_register`, `edit_user_profile_update`, `wp_insert_post`, etc. run in whatever context triggered them — including REST, XML-RPC, and imports. Re-verify capability and nonce inside the callback; check `wp_is_doing_autosave()` and `wp_doing_ajax()` where relevant.
