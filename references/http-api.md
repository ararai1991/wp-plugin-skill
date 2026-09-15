# HTTP API

Outbound requests to external services. Always use the WordPress HTTP API rather than raw cURL or `file_get_contents()` — it abstracts the available transport, respects proxy settings, and provides the safe variants.

## Functions

```php
wp_remote_get(     $url, $args = array() );
wp_remote_post(    $url, $args = array() );
wp_remote_head(    $url, $args = array() );
wp_remote_request( $url, $args = array() );   // any method

// Safe variants — block internal/private addresses
wp_safe_remote_get( $url, $args = array() );
wp_safe_remote_post( $url, $args = array() );
wp_safe_remote_head( $url, $args = array() );
wp_safe_remote_request( $url, $args = array() );
```

**Use the `wp_safe_remote_*` variants whenever the URL is influenced by user input.** They reject loopback, private, and reserved IP ranges and restrict ports to 80, 443, and 8080 — the primary defense against SSRF.

## Arguments

```php
$response = wp_safe_remote_post( 'https://api.example.com/v1/items', array(
    'method'      => 'POST',
    'timeout'     => 10,              // seconds; default 5
    'redirection' => 0,               // follow N redirects; 0 for untrusted URLs
    'httpversion' => '1.1',
    'blocking'    => true,            // false = fire and forget, no response
    'headers'     => array(
        'Authorization' => 'Bearer ' . $token,
        'Content-Type'  => 'application/json',
        'Accept'        => 'application/json',
    ),
    'body'        => wp_json_encode( array( 'name' => $name ) ),
    'cookies'     => array(),
    'sslverify'   => true,            // NEVER set false
    'user-agent'  => 'MyPlugin/' . MYPLUGIN_VERSION . '; ' . home_url(),
) );
```

`body` as an array sends form-encoded data; as a string it is sent raw (use with a JSON content type).

**Never set `'sslverify' => false`.** It disables certificate validation and enables man-in-the-middle attacks. If a certificate fails, fix the certificate.

Set `redirection => 0` for user-influenced URLs — `wp_safe_remote_*()` validates the original URL but does not reliably re-validate redirect targets, so a redirect can bypass the protection.

## Handling the response

**Always check `is_wp_error()` first.** A network failure returns `WP_Error`, not an array.

```php
$response = wp_safe_remote_get( $url, array( 'timeout' => 10 ) );

if ( is_wp_error( $response ) ) {
    return new WP_Error(
        'myplugin_request_failed',
        sprintf(
            /* translators: %s: error message */
            __( 'Request failed: %s', 'my-plugin' ),
            $response->get_error_message()
        )
    );
}

$code = wp_remote_retrieve_response_code( $response );

if ( 200 !== $code ) {
    return new WP_Error(
        'myplugin_bad_status',
        sprintf(
            /* translators: %d: HTTP status code */
            __( 'API returned status %d.', 'my-plugin' ),
            $code
        )
    );
}

$body = wp_remote_retrieve_body( $response );
$data = json_decode( $body, true );

if ( JSON_ERROR_NONE !== json_last_error() || ! is_array( $data ) ) {
    return new WP_Error( 'myplugin_bad_json', __( 'Invalid response.', 'my-plugin' ) );
}
```

Retrieval helpers:

```php
wp_remote_retrieve_body( $response );
wp_remote_retrieve_response_code( $response );      // int
wp_remote_retrieve_response_message( $response );   // 'OK'
wp_remote_retrieve_headers( $response );            // case-insensitive object
wp_remote_retrieve_header( $response, 'content-type' );
wp_remote_retrieve_cookies( $response );
```

Use these rather than indexing the array directly — the shape is not guaranteed.

## Always cache

An outbound request blocks page rendering. Never make one on a front-end page load without caching.

```php
function myplugin_get_feed() {
    $cache_key = 'myplugin_feed';
    $data      = get_transient( $cache_key );

    if ( false !== $data ) {
        return $data;
    }

    $response = wp_safe_remote_get( 'https://api.example.com/feed', array( 'timeout' => 10 ) );

    if ( is_wp_error( $response ) || 200 !== wp_remote_retrieve_response_code( $response ) ) {
        // Cache the failure briefly so a down API doesn't mean a request per page view
        set_transient( $cache_key . '_fail', 1, 5 * MINUTE_IN_SECONDS );
        return get_option( 'myplugin_feed_fallback', array() );
    }

    $data = json_decode( wp_remote_retrieve_body( $response ), true );

    if ( is_array( $data ) ) {
        set_transient( $cache_key, $data, HOUR_IN_SECONDS );
        update_option( 'myplugin_feed_fallback', $data, 'no' );   // last-known-good
    }

    return $data;
}
```

Better still: fetch on a cron schedule and store the result, so no visitor ever waits on the API.

## Security

**SSRF** — a user-supplied URL can reach cloud metadata endpoints, internal admin panels, and localhost services:

```php
$url = esc_url_raw( wp_unslash( $_POST['url'] ?? '' ) );

if ( ! wp_http_validate_url( $url ) ) {
    wp_die( esc_html__( 'Invalid URL', 'my-plugin' ), 400 );
}

// Stronger: allowlist the hosts you actually need
$host = wp_parse_url( $url, PHP_URL_HOST );
if ( ! in_array( $host, array( 'api.example.com' ), true ) ) {
    wp_die( esc_html__( 'Host not allowed', 'my-plugin' ), 400 );
}

$response = wp_safe_remote_get( $url, array(
    'timeout'            => 10,
    'redirection'        => 0,
    'reject_unsafe_urls' => true,
) );
```

Other rules:

- **Never log the full request or response** if it contains credentials.
- **Never hardcode API keys** in plugin source — plugin code is public.
- **Validate the response** before trusting it. A compromised or hostile API can return anything; never `unserialize()` it, never `eval()` it, and escape it on output.
- Treat every response as untrusted input.

## Timeouts and blocking

Default timeout is 5 seconds — long enough to make a page feel broken. Keep it low for anything in the request path, higher only in cron.

```php
// Fire and forget — returns immediately, no response available
wp_remote_post( $url, array( 'blocking' => false, 'timeout' => 1 ) );
```

Useful for webhooks and pings where the result does not matter. Not a substitute for cron on important work — a non-blocking request can be dropped.

## Filters

```php
// Modify args for all outbound requests
add_filter( 'http_request_args', function ( $args, $url ) {
    return $args;
}, 10, 2 );

// Short-circuit a request (useful in tests)
add_filter( 'pre_http_request', function ( $preempt, $args, $url ) {
    if ( false !== strpos( $url, 'api.example.com' ) ) {
        return array(
            'body'     => wp_json_encode( array( 'ok' => true ) ),
            'response' => array( 'code' => 200 ),
        );
    }
    return $preempt;
}, 10, 3 );

// Global timeout adjustment
add_filter( 'http_request_timeout', fn() => 15 );
```

`pre_http_request` is how you mock external APIs in unit tests.

## Pitfalls

- **Not checking `is_wp_error()`** — then calling a string function on a `WP_Error`
- **Assuming HTTP 200** — check the status code explicitly
- **No caching** — an API call on every page load
- **`sslverify => false`**
- **`wp_remote_get()` with a user-supplied URL** instead of the safe variant
- **Following redirects** on an untrusted URL
- **Default 5s timeout** on a request in the page-render path
- **Hardcoded credentials**
- **Trusting the response body** without validation
- **Logging secrets** in request/response dumps
- Using raw cURL or `file_get_contents()` instead of the HTTP API
