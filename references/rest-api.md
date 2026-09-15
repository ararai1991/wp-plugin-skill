# REST API

Custom REST routes for JS front-ends, blocks, headless setups, and integrations.

## Registering a route

```php
add_action( 'rest_api_init', 'myplugin_register_routes' );

function myplugin_register_routes() {
    register_rest_route(
        'myplugin/v1',                 // namespace: vendor/version
        '/items',                      // route
        array(
            'methods'             => WP_REST_Server::READABLE,
            'callback'            => 'myplugin_get_items',
            'permission_callback' => '__return_true',   // public read
            'args'                => array(
                'per_page' => array(
                    'default'           => 10,
                    'sanitize_callback' => 'absint',
                    'validate_callback' => static function ( $v ) {
                        return $v >= 1 && $v <= 100;
                    },
                ),
            ),
        )
    );
}
```

Endpoint URL: `https://site.com/wp-json/myplugin/v1/items`. Always namespace as `vendor/vN` — bump the version for breaking changes rather than mutating an existing route.

Method constants: `READABLE` (GET), `CREATABLE` (POST), `EDITABLE` (POST/PUT/PATCH), `DELETABLE` (DELETE), `ALLMETHODS`.

## permission_callback is mandatory

Required since WP 5.5. Omitting it triggers a notice and leaves the route unprotected.

```php
// Public read-only data — the ONLY correct use of __return_true
'permission_callback' => '__return_true',

// Capability check
'permission_callback' => static function () {
    return current_user_can( 'edit_posts' );
},

// Object-level check
'permission_callback' => static function ( WP_REST_Request $request ) {
    return current_user_can( 'edit_post', (int) $request['id'] );
},

// Returning WP_Error gives a better response than false
'permission_callback' => static function () {
    if ( ! current_user_can( 'manage_options' ) ) {
        return new WP_Error(
            'rest_forbidden',
            __( 'You cannot do that.', 'my-plugin' ),
            array( 'status' => rest_authorization_required_code() )
        );
    }
    return true;
},
```

**Put the check in `permission_callback`, not the route callback.** WordPress relies on the permission callback for its handling of cookie-authenticated requests; a check inside the callback runs too late and misses that protection.

## Route parameters

```php
register_rest_route( 'myplugin/v1', '/items/(?P<id>\d+)', array(
    'methods'             => WP_REST_Server::EDITABLE,
    'callback'            => 'myplugin_update_item',
    'permission_callback' => static fn( $r ) => current_user_can( 'edit_post', (int) $r['id'] ),
    'args'                => array(
        'id' => array(
            'required'          => true,
            'sanitize_callback' => 'absint',
        ),
        'title' => array(
            'required'          => true,
            'type'              => 'string',
            'sanitize_callback' => 'sanitize_text_field',
            'validate_callback' => static fn( $v ) => is_string( $v ) && strlen( $v ) <= 200,
        ),
        'status' => array(
            'default' => 'draft',
            'enum'    => array( 'draft', 'publish', 'archived' ),
        ),
    ),
) );
```

The `args` schema is the right place for validation — it applies consistently and produces proper error responses. `enum`, `type`, `minimum`, `maximum`, `format` are enforced automatically.

## Callbacks

```php
function myplugin_update_item( WP_REST_Request $request ) {
    $id    = (int) $request['id'];          // route param
    $title = $request->get_param( 'title' ); // any param
    $body  = $request->get_json_params();    // JSON body
    $files = $request->get_file_params();    // uploads
    $header = $request->get_header( 'x-custom' );

    $item = myplugin_find_item( $id );
    if ( ! $item ) {
        return new WP_Error(
            'myplugin_not_found',
            __( 'Item not found.', 'my-plugin' ),
            array( 'status' => 404 )
        );
    }

    $updated = myplugin_save_item( $id, array( 'title' => $title ) );

    return rest_ensure_response( array(
        'id'    => $id,
        'title' => $title,
    ) );
}
```

Return an array/object (auto-converted), a `WP_REST_Response`, or a `WP_Error` — the `status` in a `WP_Error`'s data sets the HTTP code.

For control over status and headers:

```php
$response = new WP_REST_Response( $data, 201 );
$response->header( 'X-Total-Count', $total );
return $response;
```

REST responses are JSON — do **not** HTML-escape values. Escape at render time in the client. Do sanitize on input, and never return data the caller lacks permission to see.

## Authentication from JavaScript

Cookie authentication requires the `wp_rest` nonce:

```php
wp_enqueue_script( 'myplugin-app', MYPLUGIN_URL . 'js/app.js', array( 'wp-api-fetch' ), MYPLUGIN_VERSION, true );

wp_localize_script( 'myplugin-app', 'myPluginApi', array(
    'root'  => esc_url_raw( rest_url( 'myplugin/v1/' ) ),
    'nonce' => wp_create_nonce( 'wp_rest' ),
) );
```

```js
// With apiFetch (handles the nonce automatically when wp-api-fetch is a dependency)
wp.apiFetch( { path: '/myplugin/v1/items', method: 'POST', data: { title: 'Hi' } } )
  .then( ( res ) => console.log( res ) );

// With fetch — send the nonce yourself
fetch( myPluginApi.root + 'items', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-WP-Nonce': myPluginApi.nonce },
    body: JSON.stringify( { title: 'Hi' } ),
} );
```

External clients use Application Passwords or OAuth, not nonces. A nonce is not an API token.

## Schema

A schema documents the endpoint and enables automatic validation:

```php
function myplugin_get_item_schema() {
    return array(
        '$schema'    => 'http://json-schema.org/draft-04/schema#',
        'title'      => 'myplugin_item',
        'type'       => 'object',
        'properties' => array(
            'id'    => array(
                'description' => __( 'Unique identifier.', 'my-plugin' ),
                'type'        => 'integer',
                'context'     => array( 'view', 'edit' ),
                'readonly'    => true,
            ),
            'title' => array(
                'description' => __( 'Item title.', 'my-plugin' ),
                'type'        => 'string',
                'context'     => array( 'view', 'edit' ),
                'arg_options' => array( 'sanitize_callback' => 'sanitize_text_field' ),
            ),
        ),
    );
}

// 'schema' => 'myplugin_get_item_schema' in register_rest_route
```

## Extending core routes

Add a field to an existing resource:

```php
add_action( 'rest_api_init', function () {
    register_rest_field( 'post', 'myplugin_reading_time', array(
        'get_callback'    => static fn( $post ) => myplugin_reading_time( $post['id'] ),
        'update_callback' => static function ( $value, $post ) {
            if ( ! current_user_can( 'edit_post', $post->ID ) ) {
                return new WP_Error( 'rest_forbidden', __( 'Forbidden.', 'my-plugin' ) );
            }
            return update_post_meta( $post->ID, '_reading_time', absint( $value ) );
        },
        'schema'          => array( 'type' => 'integer', 'context' => array( 'view', 'edit' ) ),
    ) );
} );
```

Exposing meta via `register_post_meta()` with `'show_in_rest' => true` is usually simpler — see `references/metadata.md`.

Filters for core routes: `rest_{post_type}_query` (modify query args), `rest_prepare_{post_type}` (modify the response), `rest_pre_dispatch`, `rest_authentication_errors`.

## Pagination

```php
$query = new WP_Query( array(
    'post_type'      => 'myplugin_book',
    'posts_per_page' => $per_page,
    'paged'          => $page,
) );

$response = rest_ensure_response( $items );
$response->header( 'X-WP-Total', (int) $query->found_posts );
$response->header( 'X-WP-TotalPages', (int) $query->max_num_pages );
return $response;
```

## Errors

```php
return new WP_Error( 'myplugin_invalid', __( 'Invalid input.', 'my-plugin' ), array( 'status' => 400 ) );
```

Common codes: 400 bad request, 401 not authenticated, 403 authenticated but forbidden, 404 not found, 409 conflict, 429 rate limited, 500 server error. `rest_authorization_required_code()` returns 401 or 403 depending on login state.

## Pitfalls

- **`__return_true` on a writing route** — unauthenticated create/update/delete.
- **Permission check inside the callback** instead of `permission_callback`.
- **Trusting `$request['id']`** without an ownership check — capability alone often is not enough.
- **Returning unescaped HTML** expecting the client to render it raw.
- **Leaking private fields** — emails, hashes, unpublished content — without a reader capability check.
- **No rate limiting on expensive public endpoints.**
- **Breaking an existing route's response shape** instead of adding `/v2`.
- **Forgetting `rest_ensure_response()`** when returning a bare array with headers.
