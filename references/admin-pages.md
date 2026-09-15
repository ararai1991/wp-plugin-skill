# Administration Menus and Pages

## Top-level menu

```php
add_action( 'admin_menu', 'myplugin_admin_menu' );

function myplugin_admin_menu() {
    add_menu_page(
        __( 'My Plugin', 'my-plugin' ),        // page title (<title>)
        __( 'My Plugin', 'my-plugin' ),        // menu label
        'manage_options',                      // capability
        'myplugin',                            // menu slug
        'myplugin_render_page',                // render callback
        'dashicons-chart-bar',                 // icon
        25                                     // position
    );
}
```

Add a top-level menu only if the plugin genuinely warrants one. Most plugins belong under Settings or Tools — a crowded admin menu is a real complaint from site owners.

## Submenus

```php
add_submenu_page(
    'myplugin',                                 // parent slug
    __( 'Import', 'my-plugin' ),                // page title
    __( 'Import', 'my-plugin' ),                // menu label
    'manage_options',
    'myplugin-import',
    'myplugin_render_import_page'
);
```

The first submenu item duplicates the parent unless you explicitly re-register it with the parent's slug:

```php
add_submenu_page( 'myplugin', __( 'Dashboard', 'my-plugin' ), __( 'Dashboard', 'my-plugin' ),
    'manage_options', 'myplugin', 'myplugin_render_page' );
```

**Placing under an existing menu** — usually the right choice:

```php
add_options_page( $page_title, $menu_title, $cap, $slug, $cb );      // Settings
add_management_page( ... );                                          // Tools
add_theme_page( ... );                                               // Appearance
add_users_page( ... );                                               // Users
add_plugins_page( ... );                                             // Plugins
add_media_page( ... );                                               // Media
add_pages_page( ... );                                               // Pages
add_posts_page( ... );                                               // Posts
add_comments_page( ... );                                            // Comments
add_dashboard_page( ... );                                           // Dashboard
```

For a custom post type, `show_in_menu` handles placement — see `references/post-types-taxonomies.md`.

**A page with no menu entry** (for a detail or edit screen):

```php
add_submenu_page( null, $page_title, '', 'manage_options', 'myplugin-detail', 'myplugin_render_detail' );
```

## Menu positions

| Position | Location |
|----------|----------|
| 2 | Dashboard |
| 4 | Separator |
| 5 | Posts |
| 10 | Media |
| 15 | Links |
| 20 | Pages |
| 25 | Comments |
| 59 | Separator |
| 60 | Appearance |
| 65 | Plugins |
| 70 | Users |
| 75 | Tools |
| 80 | Settings |
| 99 | Separator |

Use a float like `25.5` to avoid overwriting another plugin's menu at the same integer position.

## The capability parameter is not a security check

The capability passed to `add_menu_page()` controls whether the **menu item renders**. It does not stop someone from requesting the page URL directly. **Always re-check in the render callback:**

```php
function myplugin_render_page() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( esc_html__( 'You do not have permission to access this page.', 'my-plugin' ) );
    }
    ?>
    <div class="wrap">
        <h1><?php echo esc_html( get_admin_page_title() ); ?></h1>
        <p><?php esc_html_e( 'Welcome.', 'my-plugin' ); ?></p>
    </div>
    <?php
}
```

Wrap page content in `<div class="wrap">` and start with an `<h1>` — that is what core's admin CSS expects, and admin notices are injected after the first heading.

## Admin page assets

`add_menu_page()` returns the page's hook suffix — use it to load assets only on your screen:

```php
function myplugin_admin_menu() {
    $hook = add_menu_page( /* ... */ );
    add_action( 'load-' . $hook, 'myplugin_page_load' );   // runs only on this page
}

add_action( 'admin_enqueue_scripts', function ( $hook_suffix ) {
    if ( 'toplevel_page_myplugin' !== $hook_suffix ) {
        return;
    }
    wp_enqueue_script( 'myplugin-admin', /* ... */ );
} );
```

Hook suffix patterns: `toplevel_page_{slug}` for a top-level page, `{parent}_page_{slug}` for a submenu (e.g. `settings_page_myplugin`). `get_current_screen()->id` gives the same value.

## Admin notices

```php
add_action( 'admin_notices', function () {
    if ( ! current_user_can( 'manage_options' ) ) {
        return;
    }

    $screen = get_current_screen();
    if ( ! $screen || 'toplevel_page_myplugin' !== $screen->id ) {
        return;   // don't shout on every admin page
    }

    printf(
        '<div class="notice notice-success is-dismissible"><p>%s</p></div>',
        esc_html__( 'Settings saved.', 'my-plugin' )
    );
} );
```

Classes: `notice-success`, `notice-warning`, `notice-error`, `notice-info`, plus `is-dismissible`.

Showing notices on every admin screen is one of the most disliked plugin behaviours. Scope them to your own pages, and make promotional notices dismissible and permanently dismissible.

## Handling form submissions

For the Settings API, see `references/settings.md` — `options.php` handles nonce and capability for you.

For custom forms, do all three gates yourself:

```php
// Form
?>
<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
    <input type="hidden" name="action" value="myplugin_import">
    <?php wp_nonce_field( 'myplugin_import', 'myplugin_nonce' ); ?>
    <input type="file" name="import_file">
    <?php submit_button( __( 'Import', 'my-plugin' ) ); ?>
</form>
<?php

// Handler
add_action( 'admin_post_myplugin_import', 'myplugin_handle_import' );

function myplugin_handle_import() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( esc_html__( 'Forbidden', 'my-plugin' ), 403 );
    }
    check_admin_referer( 'myplugin_import', 'myplugin_nonce' );

    // ... do the work

    wp_safe_redirect( add_query_arg( 'imported', '1', admin_url( 'admin.php?page=myplugin' ) ) );
    exit;
}
```

Always redirect after a successful POST so a refresh does not resubmit.

## List tables

For tabular data, extend `WP_List_Table` — it provides sorting, pagination, bulk actions, and search in core's styling:

```php
if ( ! class_exists( 'WP_List_Table' ) ) {
    require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
}

class MyPlugin_Items_Table extends WP_List_Table {
    public function get_columns() {
        return array(
            'cb'   => '<input type="checkbox">',
            'name' => __( 'Name', 'my-plugin' ),
            'date' => __( 'Date', 'my-plugin' ),
        );
    }

    public function prepare_items() {
        $this->_column_headers = array( $this->get_columns(), array(), $this->get_sortable_columns() );
        $this->items = myplugin_get_items();
    }

    public function column_name( $item ) {
        return esc_html( $item['name'] );   // escape every column output
    }
}
```

`WP_List_Table` is technically a private core class — it works, is widely used, but can change between releases.

## Dashboard widgets

```php
add_action( 'wp_dashboard_setup', function () {
    if ( ! current_user_can( 'manage_options' ) ) {
        return;
    }
    wp_add_dashboard_widget( 'myplugin_widget', __( 'My Plugin', 'my-plugin' ), 'myplugin_render_widget' );
} );
```

## Plugin action links

```php
add_filter( 'plugin_action_links_' . plugin_basename( MYPLUGIN_FILE ), function ( $links ) {
    $settings = sprintf(
        '<a href="%s">%s</a>',
        esc_url( admin_url( 'options-general.php?page=myplugin' ) ),
        esc_html__( 'Settings', 'my-plugin' )
    );
    array_unshift( $links, $settings );
    return $links;
} );
```

## Pitfalls

- **Treating the menu capability as access control** — always re-check in the callback
- **A top-level menu for a plugin that should live under Settings**
- **Loading assets on every admin page**
- **Notices on every screen**
- **Unescaped output** in page rendering — stored admin input is still input
- **No `<div class="wrap">`** — notices and styling break
- **Registering menus outside `admin_menu`**
- **Integer menu positions** colliding with other plugins
- **No redirect after POST** — refresh resubmits
- **External links in the top-level admin menu** — flagged by Plugin Check
