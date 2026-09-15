# Performance

A plugin runs on every page load of every site that installs it. Slow plugin code is the most common cause of slow WordPress sites.

## Load only what you need

```php
// Don't load admin code on the front end
if ( is_admin() ) {
    require_once MYPLUGIN_DIR . 'admin/class-admin.php';
}

// Don't run front-end logic during AJAX/cron/REST
if ( wp_doing_ajax() || wp_doing_cron() ) {
    return;
}
```

Prefer an autoloader (Composer's, or a simple PSR-4 one) over requiring every class up front.

Hook late and conditionally. Work done on `plugins_loaded` happens on every request including admin-ajax and cron; work done on `template_redirect` happens only on front-end page loads.

## Enqueue conditionally

Loading assets on every page is the most common plugin performance bug.

```php
// Front end: only where the shortcode/block is used
add_action( 'wp_enqueue_scripts', function () {
    if ( ! is_singular() ) {
        return;
    }
    global $post;
    if ( has_shortcode( $post->post_content ?? '', 'myplugin' ) ) {
        wp_enqueue_style( 'myplugin', MYPLUGIN_URL . 'css/app.css', array(), MYPLUGIN_VERSION );
    }
} );

// Admin: only on your own screens
add_action( 'admin_enqueue_scripts', function ( $hook_suffix ) {
    if ( 'settings_page_myplugin' !== $hook_suffix ) {
        return;
    }
    wp_enqueue_script( 'myplugin-admin', MYPLUGIN_URL . 'js/admin.js', array( 'jquery' ), MYPLUGIN_VERSION, true );
} );
```

Also: load scripts in the footer (`$in_footer = true`), version assets with the plugin version for cache busting, and never enqueue a whole framework for one small feature.

## Cache expensive work

**Transients** for anything expensive and reusable — API responses, aggregate queries, generated markup:

```php
function myplugin_get_stats() {
    $stats = get_transient( 'myplugin_stats' );

    if ( false === $stats ) {
        $stats = myplugin_calculate_stats();   // expensive
        set_transient( 'myplugin_stats', $stats, HOUR_IN_SECONDS );
    }

    return $stats;
}
```

Always handle `false` — a transient can be evicted at any time by an object cache. Never treat it as the only copy of data.

**Object cache** for repeated reads within one request:

```php
function myplugin_get_config( $id ) {
    $cached = wp_cache_get( $id, 'myplugin_config' );
    if ( false !== $cached ) {
        return $cached;
    }

    $config = myplugin_load_config( $id );
    wp_cache_set( $id, $config, 'myplugin_config', HOUR_IN_SECONDS );
    return $config;
}
```

**Invalidate on write**, not only on expiry:

```php
add_action( 'save_post_myplugin_book', function ( $post_id ) {
    delete_transient( 'myplugin_stats' );
    wp_cache_delete( $post_id, 'myplugin_config' );
} );
```

## Query efficiently

```php
$query = new WP_Query( array(
    'post_type'              => 'myplugin_book',
    'posts_per_page'         => 20,
    'no_found_rows'          => true,    // skip SQL_CALC_FOUND_ROWS when not paginating
    'update_post_meta_cache' => false,   // skip if you won't read meta
    'update_post_term_cache' => false,   // skip if you won't read terms
    'fields'                 => 'ids',   // when you only need IDs
) );
```

Rules that matter most:

- **Never query inside a loop.** Fetch once, index by ID in PHP.
- **Avoid `posts_per_page => -1`** on data that can grow without bound.
- **`meta_query` does not scale.** The postmeta table has no compound index on `meta_value`. For filtering across many rows, use a taxonomy (indexed) or a custom table.
- **Avoid `post__not_in`** on large sets — filter in PHP or restructure the query.
- **No `LIKE '%term%'`** on large tables; leading wildcards cannot use an index.
- **Batch writes.** One query inserting 100 rows beats 100 queries.

Prime caches when you know you will need related data:

```php
$post_ids = wp_list_pluck( $items, 'post_id' );
update_postmeta_cache( $post_ids );     // one query instead of N
```

## Autoloaded options

Every autoloaded option is loaded and unserialized on **every** request.

```php
add_option( 'myplugin_large_data', $data, '', 'no' );   // not autoloaded
update_option( 'myplugin_large_data', $data, 'no' );
```

Check what a site is carrying:

```sql
SELECT option_name, LENGTH(option_value) AS size
FROM wp_options WHERE autoload = 'yes' ORDER BY size DESC LIMIT 20;
```

Keep total autoloaded data under a few hundred KB. Store one settings array rather than dozens of options.

## Offload slow work

Do not make a user wait for work that does not need to finish in the request:

```php
// Schedule instead of processing inline
wp_schedule_single_event( time() + 60, 'myplugin_process_batch', array( $batch_id ) );

add_action( 'myplugin_process_batch', 'myplugin_do_process_batch' );
```

For large jobs, process in chunks and reschedule until done rather than running one long task that hits the PHP time limit.

## External requests

An outbound HTTP call blocks the page render. Never make one on a front-end page load without caching:

```php
$data = get_transient( 'myplugin_api' );
if ( false === $data ) {
    $response = wp_safe_remote_get( $url, array( 'timeout' => 5 ) );
    if ( is_wp_error( $response ) ) {
        return get_option( 'myplugin_api_fallback', array() );   // degrade, don't break
    }
    $data = json_decode( wp_remote_retrieve_body( $response ), true );
    set_transient( 'myplugin_api', $data, 15 * MINUTE_IN_SECONDS );
}
```

Always set a short `timeout` (default is 5s and can stall a page). Cache failures briefly too, so a down API does not mean a request on every page load.

## Measuring

Install **Query Monitor** — it shows queries by plugin, slow queries, HTTP calls, hook timings, and PHP errors.

```php
// wp-config.php
define( 'SAVEQUERIES', true );   // development only — it has its own overhead
define( 'WP_DEBUG', true );
```

```php
// Quick manual measurement
$start = microtime( true );
myplugin_expensive_thing();
error_log( sprintf( 'took %.4f sec', microtime( true ) - $start ) );

// Query count for a block of code
$before = get_num_queries();
myplugin_thing();
error_log( 'queries: ' . ( get_num_queries() - $before ) );
```

Targets: your plugin should add **zero** queries to a page where it does nothing, and a handful where it is active. Any single query over ~50ms deserves an index or a rewrite.

## Common causes of slow plugins

- Assets enqueued on every page instead of where needed
- An uncached external API call on page load
- `meta_query` on a large postmeta table
- Queries inside a loop
- Large autoloaded options
- `posts_per_page => -1`
- Work on `init` that only matters in admin
- No object-cache usage for repeated reads
- Loading admin classes on the front end
- Writing to the database on every page view (hit counters, logs)
