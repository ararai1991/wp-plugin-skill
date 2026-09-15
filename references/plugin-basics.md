# Plugin Basics

Header, file structure, lifecycle, and architecture.

## Plugin header

Exactly one PHP file in the plugin folder carries the header comment. That file is the plugin's entry point.

```php
<?php
/**
 * Plugin Name:       My Plugin
 * Plugin URI:        https://example.com/my-plugin
 * Description:       Short description, under 140 characters.
 * Version:           1.0.0
 * Requires at least: 6.0
 * Requires PHP:      7.4
 * Author:            Your Name
 * Author URI:        https://example.com
 * License:           GPL-2.0-or-later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       my-plugin
 * Domain Path:       /languages
 * Update URI:        https://example.com/my-plugin
 *
 * @package MyPlugin
 */

defined( 'ABSPATH' ) || exit;
```

`Plugin Name` is the only required field, but the directory expects the rest. `Text Domain` must match the plugin slug. `Requires at least` and `Requires PHP` prevent activation on unsupported installs. `Network: true` makes the plugin network-only on multisite.

## File structure

Scale the structure to the plugin. Do not build a framework for a 200-line plugin.

**Single file** — one focused feature:

```
my-plugin/
├── my-plugin.php
└── readme.txt
```

**Standard** — most plugins:

```
my-plugin/
├── my-plugin.php          Header, constants, bootstrap only
├── uninstall.php
├── readme.txt
├── includes/              Shared logic
│   ├── class-my-plugin.php
│   ├── class-my-plugin-activator.php
│   └── functions.php
├── admin/                 Admin-only code
│   ├── class-my-plugin-admin.php
│   ├── css/
│   ├── js/
│   └── views/
├── public/                Front-end code
│   ├── class-my-plugin-public.php
│   ├── css/
│   └── js/
└── languages/
    └── my-plugin.pot
```

Conventions: files named `class-{name}.php` for classes, lowercase with hyphens. Keep the main file thin — constants, autoload/require, and a bootstrap call.

## Constants

```php
define( 'MYPLUGIN_VERSION', '1.0.0' );
define( 'MYPLUGIN_FILE', __FILE__ );
define( 'MYPLUGIN_DIR', plugin_dir_path( __FILE__ ) );   // /path/to/wp-content/plugins/my-plugin/
define( 'MYPLUGIN_URL', plugin_dir_url( __FILE__ ) );    // https://site.com/wp-content/plugins/my-plugin/
define( 'MYPLUGIN_BASENAME', plugin_basename( __FILE__ ) ); // my-plugin/my-plugin.php
```

Use these helpers rather than hardcoding paths — `wp-content` can be moved or renamed.

| Function | Returns |
|----------|---------|
| `plugin_dir_path( __FILE__ )` | Filesystem path, trailing slash |
| `plugin_dir_url( __FILE__ )` | URL, trailing slash |
| `plugins_url( 'css/a.css', __FILE__ )` | URL to a specific asset |
| `plugin_basename( __FILE__ )` | `folder/file.php` |
| `WP_PLUGIN_DIR` | Plugins directory path |
| `WP_CONTENT_DIR` / `WP_CONTENT_URL` | Content directory |
| `ABSPATH` | WordPress root path |
| `wp_upload_dir()` | Array with upload `path`, `url`, `basedir`, `baseurl` |

## Lifecycle hooks

```php
register_activation_hook( __FILE__, 'myplugin_activate' );
register_deactivation_hook( __FILE__, 'myplugin_deactivate' );
```

**Activation** — run once on activation. Create tables, set default options, schedule cron, flush rewrite rules.

```php
function myplugin_activate() {
    // Bail if requirements are unmet — do it here, not at runtime
    if ( version_compare( PHP_VERSION, '7.4', '<' ) ) {
        deactivate_plugins( plugin_basename( __FILE__ ) );
        wp_die( esc_html__( 'My Plugin requires PHP 7.4 or higher.', 'my-plugin' ) );
    }

    add_option( 'myplugin_settings', array( 'enabled' => true ) );
    myplugin_create_tables();

    // CPTs must be registered before flushing, or their rules won't exist
    myplugin_register_post_types();
    flush_rewrite_rules();
}
```

**Deactivation** — undo runtime state, but keep user data. Users deactivate to troubleshoot; deleting their data here is destructive.

```php
function myplugin_deactivate() {
    wp_clear_scheduled_hook( 'myplugin_daily_task' );
    flush_rewrite_rules();
}
```

**Uninstall** — permanent removal. Prefer `uninstall.php` over `register_uninstall_hook()`; it runs in a clean context without loading the plugin.

```php
<?php
// uninstall.php
defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

delete_option( 'myplugin_settings' );
delete_site_option( 'myplugin_network_settings' );

global $wpdb;
$wpdb->query( "DROP TABLE IF EXISTS {$wpdb->prefix}myplugin_data" );
$wpdb->delete( $wpdb->postmeta, array( 'meta_key' => '_myplugin_field' ) );

if ( is_multisite() ) {
    foreach ( get_sites( array( 'fields' => 'ids' ) ) as $blog_id ) {
        switch_to_blog( $blog_id );
        delete_option( 'myplugin_settings' );
        restore_current_blog();
    }
}
```

`flush_rewrite_rules()` is expensive — call it only in activation/deactivation, never on `init`.

## Avoiding collisions

A plugin shares one global namespace with core and every other plugin. Three approaches:

**Prefix everything** (simple plugins):

```php
define( 'MYPLUGIN_VERSION', '1.0.0' );
function myplugin_get_data() {}
global $myplugin_cache;
```

**Class wrapper** (most plugins) — only the class name is global:

```php
final class My_Plugin {
    private static $instance = null;

    public static function instance() {
        if ( null === self::$instance ) {
            self::$instance = new self();
            self::$instance->init_hooks();
        }
        return self::$instance;
    }

    private function __construct() {}
    private function init_hooks() {
        add_action( 'init', array( $this, 'register_post_types' ) );
    }

    public function register_post_types() { /* ... */ }
}

add_action( 'plugins_loaded', array( 'My_Plugin', 'instance' ) );
```

**Namespaces** (PHP 5.3+, modern plugins):

```php
namespace MyCompany\MyPlugin;

function bootstrap() {
    add_action( 'init', __NAMESPACE__ . '\\register_post_types' );
}
```

Note that namespaced callbacks need the fully-qualified name as a string, or `array( $this, 'method' )`.

Guard globally-named functions:

```php
if ( ! function_exists( 'myplugin_helper' ) ) {
    function myplugin_helper() {}
}
```

## Bootstrap order

```php
// Main file: define, require, instantiate — nothing else
defined( 'ABSPATH' ) || exit;

define( 'MYPLUGIN_VERSION', '1.0.0' );
define( 'MYPLUGIN_DIR', plugin_dir_path( __FILE__ ) );

require_once MYPLUGIN_DIR . 'includes/class-my-plugin.php';

register_activation_hook( __FILE__, array( 'My_Plugin_Activator', 'activate' ) );
register_deactivation_hook( __FILE__, array( 'My_Plugin_Deactivator', 'deactivate' ) );

add_action( 'plugins_loaded', array( 'My_Plugin', 'instance' ) );
```

Do not run logic at file scope. The main file loads before most of WordPress exists — calling `get_option()`, `wp_get_current_user()`, or registering post types at that point is unreliable.

Load order for plugins:

1. Plugin file is included (only PHP-level definitions are safe)
2. `plugins_loaded` — all plugins loaded; safe for setup
3. `init` — most registrations: post types, taxonomies, shortcodes
4. `wp_loaded` — WordPress fully loaded
5. `admin_init` / `template_redirect` — context-specific

## Conditional loading

Do not load admin code on the front end, or vice versa:

```php
if ( is_admin() ) {
    require_once MYPLUGIN_DIR . 'admin/class-my-plugin-admin.php';
} else {
    require_once MYPLUGIN_DIR . 'public/class-my-plugin-public.php';
}
```

`is_admin()` is true for `admin-ajax.php` too — it means "an admin-area request", not "the user is an administrator". It is **not** a security check.

Useful conditionals: `is_admin()`, `wp_doing_ajax()`, `wp_doing_cron()`, `is_network_admin()`, `defined( 'REST_REQUEST' )`, `wp_is_json_request()`, `is_user_logged_in()`.

## Requirement checks

Fail loudly rather than fatally:

```php
add_action( 'admin_init', 'myplugin_check_requirements' );

function myplugin_check_requirements() {
    if ( ! class_exists( 'WooCommerce' ) ) {
        add_action( 'admin_notices', function () {
            printf(
                '<div class="notice notice-error"><p>%s</p></div>',
                esc_html__( 'My Plugin requires WooCommerce to be active.', 'my-plugin' )
            );
        } );
        deactivate_plugins( plugin_basename( MYPLUGIN_FILE ) );
    }
}
```

## Best practices

- **One responsibility per file.** A 3000-line main file is a maintenance problem.
- **Never modify core.** Use hooks and filters.
- **No output at file scope.** Whitespace after `?>` breaks headers — omit the closing tag in PHP-only files.
- **Autoload sparingly.** `add_option( $name, $value, '', 'no' )` for large or rarely-read options; autoloaded options load on every request.
- **Use core APIs before `$wpdb`.** `WP_Query`, `get_posts()`, `get_option()`, `wp_insert_post()` handle caching, hooks, and escaping.
- **Make things filterable.** `apply_filters( 'myplugin_thing', $value )` lets others extend without forking.
- **Version your data.** Store a schema version option so upgrade routines can migrate.
- **Keep the readme accurate.** `Tested up to` signals maintenance.
