# Database

Prefer core APIs over direct SQL. `WP_Query`, `get_posts()`, `get_option()`, `wp_insert_post()`, and the meta functions handle caching, hooks, and escaping. Drop to `$wpdb` only when no API covers the need.

## $wpdb basics

```php
global $wpdb;
// or inside a class: $wpdb = $GLOBALS['wpdb'];
```

| Property | Value |
|----------|-------|
| `$wpdb->prefix` | Table prefix for the current site (`wp_`) |
| `$wpdb->base_prefix` | Network base prefix (multisite) |
| `$wpdb->posts`, `->postmeta`, `->users`, `->usermeta`, `->options`, `->terms`, `->term_taxonomy`, `->term_relationships`, `->comments`, `->commentmeta` | Core table names, already prefixed |
| `$wpdb->insert_id` | ID from the last insert |
| `$wpdb->last_error` | Last error message |
| `$wpdb->num_rows` | Rows from the last query |

## Reading

```php
// Single value
$count = $wpdb->get_var( $wpdb->prepare(
    "SELECT COUNT(*) FROM {$wpdb->prefix}myplugin_items WHERE status = %s", 'active'
) );

// Single row (object by default; ARRAY_A for associative array)
$row = $wpdb->get_row( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}myplugin_items WHERE id = %d", $id
) );

// Multiple rows
$rows = $wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}myplugin_items WHERE status = %s ORDER BY created_at DESC LIMIT %d",
    'active', 20
) );

// Single column
$ids = $wpdb->get_col( "SELECT id FROM {$wpdb->prefix}myplugin_items" );
```

## prepare() — mandatory for any query with a variable

```php
$wpdb->prepare( string $query, mixed ...$args );
```

Placeholders: `%d` integer, `%f` float, `%s` string, `%i` identifier (WP 6.2+), `%%` literal percent.

```php
// CORRECT
$wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}items WHERE type = %s AND count > %d", $type, $min
) );

// WRONG — interpolation in the query argument defeats prepare entirely
$wpdb->get_results( $wpdb->prepare( "SELECT * FROM items WHERE id = $id" ) );

// WRONG — do not quote %s yourself; prepare adds quotes
$wpdb->prepare( "WHERE name = '%s'", $name );
```

**Table names** from `$wpdb->prefix` are safe to interpolate — they are not user input. **Column and table names from user input** cannot be placeholders (before `%i`); allowlist them:

```php
$allowed = array( 'name', 'created_at', 'status' );
$orderby = in_array( $_GET['orderby'] ?? '', $allowed, true ) ? $_GET['orderby'] : 'name';
$order   = ( 'DESC' === strtoupper( $_GET['order'] ?? '' ) ) ? 'DESC' : 'ASC';

$rows = $wpdb->get_results( "SELECT * FROM {$wpdb->prefix}items ORDER BY `{$orderby}` {$order}" );
```

**IN() clauses** — build placeholders dynamically:

```php
$ids          = array_map( 'absint', (array) $input_ids );
$placeholders = implode( ',', array_fill( 0, count( $ids ), '%d' ) );
$rows = $wpdb->get_results(
    $wpdb->prepare( "SELECT * FROM {$wpdb->prefix}items WHERE id IN ($placeholders)", $ids )
);
```

**LIKE** — escape wildcards first:

```php
$like = '%' . $wpdb->esc_like( $search ) . '%';
$rows = $wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}items WHERE name LIKE %s", $like
) );
```

`esc_sql()` is **not** a substitute for `prepare()` — it only escapes for quoted string contexts, so a value dropped into `ORDER BY` or an unquoted comparison is still injectable.

## Writing

These build and prepare the query for you — prefer them for simple writes:

```php
// INSERT
$wpdb->insert(
    $wpdb->prefix . 'myplugin_items',
    array( 'name' => $name, 'count' => $count, 'created_at' => current_time( 'mysql' ) ),
    array( '%s', '%d', '%s' )      // format array — always supply it
);
$new_id = $wpdb->insert_id;

// UPDATE
$wpdb->update(
    $wpdb->prefix . 'myplugin_items',
    array( 'name' => $name ),      // data
    array( 'id' => $id ),          // where
    array( '%s' ),                 // data format
    array( '%d' )                  // where format
);

// DELETE
$wpdb->delete( $wpdb->prefix . 'myplugin_items', array( 'id' => $id ), array( '%d' ) );

// REPLACE
$wpdb->replace( $table, $data, $format );
```

All return the number of affected rows, or `false` on error. Note that `update()` returns `0` when the values are unchanged — check `false === $result` for failure, not falsiness.

For anything else, `$wpdb->query( $wpdb->prepare( ... ) )`.

## Custom tables

Only when post types and meta genuinely do not fit — large volumes of non-content data, or queries that need real indexes.

```php
function myplugin_create_tables() {
    global $wpdb;

    $table   = $wpdb->prefix . 'myplugin_items';
    $charset = $wpdb->get_charset_collate();

    // dbDelta is strict: two spaces after PRIMARY KEY, KEY on its own line,
    // lowercase types, one field per line.
    $sql = "CREATE TABLE $table (
        id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
        user_id bigint(20) unsigned NOT NULL DEFAULT 0,
        name varchar(191) NOT NULL DEFAULT '',
        payload longtext NULL,
        status varchar(20) NOT NULL DEFAULT 'pending',
        created_at datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
        PRIMARY KEY  (id),
        KEY user_id (user_id),
        KEY status_created (status, created_at)
    ) $charset;";

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta( $sql );

    update_option( 'myplugin_db_version', MYPLUGIN_DB_VERSION );
}
```

`dbDelta()` quirks that silently break it: exactly two spaces after `PRIMARY KEY`, each field on its own line, `KEY` (not `INDEX`), and key names must be present. Index `varchar` at 191 or less on older utf8mb4 installs.

**Schema migrations** — compare a stored version:

```php
add_action( 'plugins_loaded', 'myplugin_maybe_upgrade' );

function myplugin_maybe_upgrade() {
    if ( get_option( 'myplugin_db_version' ) !== MYPLUGIN_DB_VERSION ) {
        myplugin_create_tables();   // dbDelta applies the diff
    }
}
```

Activation hooks do not fire on update, so an upgrade check on `plugins_loaded` is how schema changes actually reach existing installs.

## Options API

```php
get_option( $name, $default = false );
add_option( $name, $value, '', $autoload = 'yes' );
update_option( $name, $value, $autoload = null );   // creates if absent
delete_option( $name );
```

Values are serialized automatically — arrays and objects work. Autoloaded options load on **every** request: use `'no'` for large or rarely-read values.

```php
add_option( 'myplugin_big_cache', $data, '', 'no' );
```

Store one settings array rather than many options — one row, one autoload entry:

```php
$settings = get_option( 'myplugin_settings', array() );
$settings['color'] = 'blue';
update_option( 'myplugin_settings', $settings );
```

Multisite equivalents: `get_site_option()`, `update_site_option()`, `delete_site_option()`.

## Transients — cached, expiring data

```php
set_transient( $key, $value, $expiration );   // seconds; 0 = no expiry
get_transient( $key );                        // false if missing or expired
delete_transient( $key );
```

```php
function myplugin_get_feed() {
    $data = get_transient( 'myplugin_feed' );

    if ( false === $data ) {
        $response = wp_safe_remote_get( 'https://api.example.com/feed' );
        if ( is_wp_error( $response ) ) {
            return array();
        }
        $data = json_decode( wp_remote_retrieve_body( $response ), true );
        set_transient( 'myplugin_feed', $data, HOUR_IN_SECONDS );
    }

    return $data;
}
```

Time constants: `MINUTE_IN_SECONDS`, `HOUR_IN_SECONDS`, `DAY_IN_SECONDS`, `WEEK_IN_SECONDS`, `MONTH_IN_SECONDS`, `YEAR_IN_SECONDS`.

Transients are **not guaranteed to persist** — an object cache can evict them at any time. Always handle the `false` case; never use a transient as the only copy of data.

## Object cache

Per-request by default; persistent with Redis/Memcached installed.

```php
wp_cache_get( $key, $group );
wp_cache_set( $key, $value, $group, $expire );
wp_cache_delete( $key, $group );
```

Use it to avoid repeating an expensive query within a single request.

## Query efficiency

- `'no_found_rows' => true` when you do not need pagination — skips `SQL_CALC_FOUND_ROWS`.
- `'fields' => 'ids'` when you only need IDs.
- `'update_post_meta_cache' => false` / `'update_post_term_cache' => false` when you will not read meta or terms.
- Avoid `'posts_per_page' => -1` on unbounded data.
- `meta_query` is slow at scale — the meta table has no compound index on value. For heavy filtering, use a taxonomy or a custom table.
- Never run a query inside a loop; fetch in one query and index in PHP.

```php
$query = new WP_Query( array(
    'post_type'              => 'myplugin_book',
    'posts_per_page'         => 20,
    'no_found_rows'          => true,
    'update_post_term_cache' => false,
    'fields'                 => 'ids',
) );
```

Always `wp_reset_postdata()` after a custom `WP_Query` loop that used `the_post()`.

## Errors

`$wpdb` suppresses errors by default:

```php
$result = $wpdb->insert( $table, $data, $format );

if ( false === $result ) {
    // $wpdb->last_error has the message — log it, do not echo it
    return new WP_Error( 'db_insert_failed', __( 'Could not save the item.', 'my-plugin' ) );
}
```

Use `$wpdb->show_errors()` / `$wpdb->hide_errors()` only in development. Never expose SQL errors to users — they leak schema.
