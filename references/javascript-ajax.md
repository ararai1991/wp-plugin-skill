# JavaScript, Assets, and AJAX

## Enqueuing

```php
wp_enqueue_script( $handle, $src = '', $deps = array(), $ver = false, $args = array() );
wp_enqueue_style(  $handle, $src = '', $deps = array(), $ver = false, $media = 'all' );
```

```php
add_action( 'wp_enqueue_scripts', function () {
    wp_enqueue_script(
        'myplugin-app',
        plugins_url( 'js/app.js', MYPLUGIN_FILE ),
        array( 'jquery' ),
        MYPLUGIN_VERSION,
        array( 'in_footer' => true, 'strategy' => 'defer' )   // WP 6.3+
    );

    wp_enqueue_style(
        'myplugin-app',
        plugins_url( 'css/app.css', MYPLUGIN_FILE ),
        array(),
        MYPLUGIN_VERSION
    );
} );
```

- Use `plugins_url()` — never hardcode paths.
- `$ver` busts caches: pass the plugin version. `false` uses the WP version; `null` omits it entirely.
- `$args` (WP 6.3+) takes `in_footer` and `strategy` (`defer` or `async`). A plain `true`/`false` still works as the legacy `$in_footer`.
- Prefix handles — `myplugin-app`, not `app`.

**Hooks:** `wp_enqueue_scripts` (front end), `admin_enqueue_scripts` (admin, receives `$hook_suffix`), `login_enqueue_scripts` (login), `enqueue_block_editor_assets` (editor).

**Always enqueue conditionally:**

```php
add_action( 'admin_enqueue_scripts', function ( $hook_suffix ) {
    if ( 'settings_page_myplugin' !== $hook_suffix ) {
        return;
    }
    wp_enqueue_script( 'myplugin-admin', /* ... */ );
} );
```

`wp_register_script()` registers without loading — useful to register early and enqueue later from inside a shortcode or block render.

## Passing data to JavaScript

**`wp_add_inline_script()` — preferred.** Preserves JSON types.

```php
wp_add_inline_script(
    'myplugin-app',
    'const myPluginData = ' . wp_json_encode( array(
        'ajaxUrl' => admin_url( 'admin-ajax.php' ),
        'restUrl' => esc_url_raw( rest_url( 'myplugin/v1/' ) ),
        'nonce'   => wp_create_nonce( 'myplugin_action' ),
        'perPage' => 10,      // stays an integer
        'isAdmin' => true,    // stays a boolean
    ) ) . ';',
    'before'
);
```

**`wp_localize_script()` — legacy, with a real gotcha.**

```php
wp_localize_script( 'myplugin-app', 'myPluginData', array(
    'ajaxUrl' => admin_url( 'admin-ajax.php' ),
    'nonce'   => wp_create_nonce( 'myplugin_action' ),
) );
```

**All values are cast to strings.** `10` becomes `"10"`, `true` becomes `"1"`, `false` and `null` become `""`. This silently breaks strict comparisons in JS. It was designed for translation strings; use `wp_add_inline_script()` for typed config.

Both require the handle to be registered or enqueued **first**, in the same request, or the data is silently dropped.

## jQuery

WordPress ships jQuery in `noConflict` mode — the global `$` is **not** defined.

```js
jQuery( document ).ready( function ( $ ) {
    $( '.myplugin-button' ).on( 'click', function () { /* ... */ } );
} );

// or
( function ( $ ) {
    'use strict';
    $( function () { /* DOM ready */ } );
} )( jQuery );
```

Writing `$(...)` at top level gives `Uncaught TypeError: $ is not a function`. Never deregister core jQuery to load your own from a CDN — it breaks the admin and other plugins.

## AJAX

The endpoint is `admin-ajax.php`. The `action` parameter selects the hook.

```php
// Logged-in users
add_action( 'wp_ajax_myplugin_save', 'myplugin_ajax_save' );
// Logged-out users — ONLY if the action is genuinely public
add_action( 'wp_ajax_nopriv_myplugin_save', 'myplugin_ajax_save' );

function myplugin_ajax_save() {
    // Gate 1+2: authorization
    if ( ! current_user_can( 'edit_posts' ) ) {
        wp_send_json_error( array( 'message' => __( 'Forbidden', 'my-plugin' ) ), 403 );
    }

    // Gate 3: intent — dies on failure
    check_ajax_referer( 'myplugin_action', 'nonce' );

    // Input
    $title = sanitize_text_field( wp_unslash( $_POST['title'] ?? '' ) );
    if ( '' === $title ) {
        wp_send_json_error( array( 'message' => __( 'Title is required.', 'my-plugin' ) ), 400 );
    }

    $id = myplugin_save( $title );

    wp_send_json_success( array( 'id' => $id, 'title' => $title ) );
}
```

`wp_send_json_success()` / `wp_send_json_error()` set the JSON content type and **call `die()`** — nothing after them runs.

Client side:

```js
jQuery( document ).ready( function ( $ ) {
    $( '#myplugin-form' ).on( 'submit', function ( e ) {
        e.preventDefault();

        $.post( myPluginData.ajaxUrl, {
            action: 'myplugin_save',            // matches wp_ajax_{action}
            nonce:  myPluginData.nonce,
            title:  $( '#title' ).val(),
        } ).done( function ( response ) {
            if ( response.success ) {
                console.log( response.data.id );
            } else {
                console.error( response.data.message );
            }
        } );
    } );
} );
```

### The nopriv trap

`wp_ajax_nopriv_{action}` is a **public, unauthenticated endpoint on the open internet**. Register it only for actions genuinely intended for logged-out visitors. If one callback serves both variants, it must handle the logged-out case safely — no user exists, `current_user_can()` is false, and a nonce from a logged-out session is far weaker.

For anything public, also consider rate limiting and never allow writes to privileged data.

### REST vs AJAX

Prefer the REST API for new work — it has schema validation, proper HTTP semantics, and a real permission model. `admin-ajax.php` remains appropriate for simple admin interactions and legacy code. See `references/rest-api.md`.

## Script translations

```php
wp_enqueue_script( 'myplugin-app', plugins_url( 'build/index.js', MYPLUGIN_FILE ),
    array( 'wp-i18n', 'wp-element' ), MYPLUGIN_VERSION, true );

wp_set_script_translations( 'myplugin-app', 'my-plugin', MYPLUGIN_DIR . 'languages' );
```

The script must declare `wp-i18n` as a dependency. `$path` is a filesystem path, not a URL. JS needs JSON translation files — see `references/i18n.md`.

## Modern build output

`@wordpress/scripts` generates an `.asset.php` with the correct dependencies and a content hash:

```php
$asset = require MYPLUGIN_DIR . 'build/index.asset.php';

wp_enqueue_script(
    'myplugin-app',
    plugins_url( 'build/index.js', MYPLUGIN_FILE ),
    $asset['dependencies'],
    $asset['version'],
    true
);
```

Use it rather than hardcoding the dependency array.

## Pitfalls

- **Enqueuing on every page** instead of where needed — the most common plugin performance bug
- **`wp_localize_script()` casting numbers and booleans to strings**
- **Localizing before the handle is registered** — data silently dropped
- **`$` at top level** in noConflict mode
- **`wp_ajax_nopriv_`** on an action that should require login
- **No nonce or capability check** in the AJAX handler
- **Echoing before `wp_send_json_*`** — corrupts the JSON
- **Forgetting `wp_die()`** in a hand-rolled AJAX handler (returns a trailing `0`)
- **Unescaped data in inline scripts** — use `wp_json_encode()`
- **Deregistering core jQuery**
- **Hardcoded asset URLs** instead of `plugins_url()`
