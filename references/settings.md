# Settings and Options

The Options API stores values. The Settings API builds the form, handles the POST, and provides nonce and capability checks for you.

## Options API

```php
get_option( $name, $default = false );
add_option( $name, $value, '', $autoload = 'yes' );
update_option( $name, $value, $autoload = null );   // creates if missing
delete_option( $name );
```

Values serialize automatically. Prefix every option name.

**Store one array, not many options.** One row, one autoload entry, one update:

```php
$defaults = array( 'enabled' => true, 'color' => '#0073aa', 'count' => 10 );
$settings = wp_parse_args( get_option( 'myplugin_settings', array() ), $defaults );
```

`wp_parse_args()` ensures new keys added in later versions have values on existing installs.

Autoloaded options load on every request. Use `'no'` for anything large or rarely read:

```php
add_option( 'myplugin_cache', $big_array, '', 'no' );
```

Multisite: `get_site_option()`, `update_site_option()`, `delete_site_option()`.

## Settings API

Three steps: register the setting, define sections and fields, render the form.

### 1. Register

```php
add_action( 'admin_init', 'myplugin_register_settings' );

function myplugin_register_settings() {
    register_setting(
        'myplugin_options_group',        // option group — must match settings_fields()
        'myplugin_settings',             // option name
        array(
            'type'              => 'array',
            'sanitize_callback' => 'myplugin_sanitize_settings',
            'default'           => array(),
            'show_in_rest'      => false,
        )
    );

    add_settings_section(
        'myplugin_general',                          // section id
        __( 'General Settings', 'my-plugin' ),       // title
        'myplugin_general_section_cb',               // description callback
        'myplugin'                                   // page slug
    );

    add_settings_field(
        'myplugin_field_color',                      // field id
        __( 'Accent Color', 'my-plugin' ),           // label
        'myplugin_field_color_cb',                   // render callback
        'myplugin',                                  // page slug
        'myplugin_general',                          // section id
        array( 'label_for' => 'myplugin_field_color' )
    );
}
```

`label_for` makes the `<th>` label clickable — pass it, and give your input that id.

### 2. Sanitize

The sanitize callback is your responsibility and your only guarantee. Never return `$input` unfiltered.

```php
function myplugin_sanitize_settings( $input ) {
    $output = array();

    $output['enabled'] = ! empty( $input['enabled'] );
    $output['color']   = sanitize_hex_color( $input['color'] ?? '' ) ?: '#0073aa';
    $output['count']   = min( 100, max( 1, absint( $input['count'] ?? 10 ) ) );
    $output['email']   = sanitize_email( $input['email'] ?? '' );
    $output['bio']     = wp_kses_post( $input['bio'] ?? '' );

    // Constrained values: allowlist, do not sanitize toward one
    $modes = array( 'light', 'dark', 'auto' );
    $output['mode'] = in_array( $input['mode'] ?? '', $modes, true ) ? $input['mode'] : 'light';

    // Report a problem back to the user
    if ( ! empty( $input['email'] ) && ! is_email( $input['email'] ) ) {
        add_settings_error(
            'myplugin_settings',
            'invalid_email',
            __( 'That email address is not valid.', 'my-plugin' ),
            'error'
        );
        $output['email'] = get_option( 'myplugin_settings' )['email'] ?? '';
    }

    return $output;
}
```

The sanitize callback can run twice per request in some flows — keep it free of side effects.

### 3. Render

```php
function myplugin_field_color_cb( $args ) {
    $settings = get_option( 'myplugin_settings', array() );
    $value    = $settings['color'] ?? '#0073aa';

    printf(
        '<input type="text" id="%s" name="myplugin_settings[color]" value="%s" class="regular-text">',
        esc_attr( $args['label_for'] ),
        esc_attr( $value )
    );
    printf( '<p class="description">%s</p>', esc_html__( 'Used for buttons and links.', 'my-plugin' ) );
}
```

Field names use the option-array syntax `myplugin_settings[key]` so everything posts into one option.

### 4. The page

```php
add_action( 'admin_menu', 'myplugin_add_settings_page' );

function myplugin_add_settings_page() {
    add_options_page(
        __( 'My Plugin Settings', 'my-plugin' ),   // page title
        __( 'My Plugin', 'my-plugin' ),            // menu label
        'manage_options',                          // capability
        'myplugin',                                // slug — matches add_settings_section page
        'myplugin_render_settings_page'
    );
}

function myplugin_render_settings_page() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( esc_html__( 'You do not have permission to access this page.', 'my-plugin' ) );
    }
    ?>
    <div class="wrap">
        <h1><?php echo esc_html( get_admin_page_title() ); ?></h1>
        <?php settings_errors( 'myplugin_settings' ); ?>
        <form action="options.php" method="post">
            <?php
            settings_fields( 'myplugin_options_group' );   // nonce + option group
            do_settings_sections( 'myplugin' );            // renders sections and fields
            submit_button();
            ?>
        </form>
    </div>
    <?php
}
```

`settings_fields()` emits the nonce and the referer field, and `options.php` verifies both plus the capability registered with the option group. That is what makes the Settings API safe — **but only when the form posts to `options.php`**. A hand-rolled form posting elsewhere gets none of it and must do its own nonce and capability checks.

Re-check the capability at the top of the render callback: the menu capability gates the menu item, not direct access to the page.

## Field patterns

```php
// Checkbox — unchecked boxes post nothing; the sanitizer's ! empty() handles that
printf(
    '<label><input type="checkbox" name="myplugin_settings[enabled]" value="1" %s> %s</label>',
    checked( ! empty( $settings['enabled'] ), true, false ),
    esc_html__( 'Enable the feature', 'my-plugin' )
);

// Select
echo '<select name="myplugin_settings[mode]">';
foreach ( array( 'light' => __( 'Light', 'my-plugin' ), 'dark' => __( 'Dark', 'my-plugin' ) ) as $key => $label ) {
    printf(
        '<option value="%s" %s>%s</option>',
        esc_attr( $key ),
        selected( $settings['mode'] ?? '', $key, false ),
        esc_html( $label )
    );
}
echo '</select>';

// Textarea
printf(
    '<textarea name="myplugin_settings[bio]" rows="5" class="large-text">%s</textarea>',
    esc_textarea( $settings['bio'] ?? '' )
);

// Radio
printf(
    '<label><input type="radio" name="myplugin_settings[size]" value="large" %s> %s</label>',
    checked( $settings['size'] ?? '', 'large', false ),
    esc_html__( 'Large', 'my-plugin' )
);
```

`checked()`, `selected()`, and `disabled()` with a third argument of `false` return instead of echoing.

## Tabbed settings

```php
$tabs   = array( 'general' => __( 'General', 'my-plugin' ), 'advanced' => __( 'Advanced', 'my-plugin' ) );
$active = isset( $_GET['tab'] ) && isset( $tabs[ $_GET['tab'] ] ) ? sanitize_key( $_GET['tab'] ) : 'general';

echo '<nav class="nav-tab-wrapper">';
foreach ( $tabs as $slug => $label ) {
    printf(
        '<a href="%s" class="nav-tab %s">%s</a>',
        esc_url( add_query_arg( array( 'page' => 'myplugin', 'tab' => $slug ), admin_url( 'options-general.php' ) ) ),
        $active === $slug ? 'nav-tab-active' : '',
        esc_html( $label )
    );
}
echo '</nav>';

do_settings_sections( 'myplugin_' . $active );
```

Register each tab's sections against its own page slug, and register one setting per tab (or merge carefully — a partial POST will otherwise wipe the other tab's keys).

## Custom settings forms

When the Settings API does not fit, do all three gates yourself:

```php
add_action( 'admin_post_myplugin_save', 'myplugin_handle_save' );

function myplugin_handle_save() {
    if ( ! current_user_can( 'manage_options' ) ) {
        wp_die( esc_html__( 'Forbidden', 'my-plugin' ), 403 );
    }
    check_admin_referer( 'myplugin_save', 'myplugin_nonce' );

    update_option( 'myplugin_settings', myplugin_sanitize_settings( $_POST['myplugin_settings'] ?? array() ) );

    wp_safe_redirect( add_query_arg( 'updated', 'true', admin_url( 'options-general.php?page=myplugin' ) ) );
    exit;
}
```

## Pitfalls

- **Returning `$input` from the sanitize callback** — no sanitization at all.
- **Mismatched slugs.** `settings_fields()` takes the *option group*; `do_settings_sections()` takes the *page slug*. Mixing them renders nothing.
- **Hand-rolled form posting to `options.php`** without `settings_fields()` — the save silently fails.
- **No capability check in the page callback.**
- **Missing `wp_parse_args()` with defaults** — new settings keys are undefined on existing installs.
- **Autoloading large options.**
- **Registering settings outside `admin_init`.**
- **Unescaped values in field rendering** — stored admin input is still input.
