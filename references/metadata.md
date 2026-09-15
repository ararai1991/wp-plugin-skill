# Metadata

Post meta, term meta, user meta, comment meta, meta boxes, and `register_meta()`.

## Core functions

```php
add_post_meta(    $post_id, $meta_key, $meta_value, $unique = false );
update_post_meta( $post_id, $meta_key, $meta_value, $prev_value = '' );
get_post_meta(    $post_id, $meta_key = '', $single = false );
delete_post_meta( $post_id, $meta_key, $meta_value = '' );
```

Identical families exist for every object type: `*_user_meta`, `*_term_meta`, `*_comment_meta`.

## The `$single` parameter

The third argument changes the **return type**, not just the count. This is the most common metadata bug.

| `$single` | Returns | When missing |
|-----------|---------|--------------|
| `true` | The value itself | `''` |
| `false` (default) | **Array of all values** | `array()` |

```php
$color  = get_post_meta( $post_id, 'myplugin_color', true );    // 'red'
$colors = get_post_meta( $post_id, 'myplugin_color', false );   // array( 'red', 'blue' )
```

Omitting `true` and echoing the result gives "Array to string conversion". With `$single = true` you cannot distinguish "not set" from "set to empty string" — use `metadata_exists( 'post', $post_id, $key )` when that matters.

Omitting `$meta_key` entirely returns every key for the post, each mapped to an array of values.

## add vs update

- `add_post_meta()` with `$unique = false` (the default) **appends another row** — calling it in a loop silently accumulates duplicates. Pass `true` to make it a no-op when the key exists.
- `update_post_meta()` creates the row if absent, so it is the right default for single-value fields.
- `update_post_meta()` returns the new meta ID when it created a row, `true` when it updated, and **`false` when the value was unchanged** — so `if ( ! update_post_meta( ... ) )` is not a valid error check.
- `$prev_value` targets one specific row among duplicates.

## Value handling

Arrays and objects are **automatically serialized** on write and unserialized on read. Never call `serialize()` yourself — you would get a double-serialized string back. Prefer arrays over objects; an object whose class is not loaded at read time comes back as `__PHP_Incomplete_Class`.

Meta values pass through `stripslashes()`, which corrupts escaped JSON:

```php
// Backslashes are stripped — the JSON no longer parses
update_post_meta( $id, 'json', '{"k":"value with \"quotes\""}' );

// Fix: double-escape on the way in
update_post_meta( $id, 'json', wp_slash( $json ) );
```

## Protected meta

Keys beginning with `_` are protected: hidden from the Custom Fields metabox, not output by `the_meta()`, and rejected by the REST API unless `register_meta()` supplies an `auth_callback`.

```php
update_post_meta( $post_id, '_myplugin_internal', $value );
```

**Prefix every meta key** with your plugin slug. `wp_postmeta` is shared by every plugin — generic keys like `price` or `color` collide.

## register_meta()

Registering meta gives it a type, a sanitizer, a default, and REST exposure.

```php
add_action( 'init', function () {
    register_post_meta( 'myplugin_product', '_myplugin_price', array(
        'type'              => 'number',
        'single'            => true,
        'default'           => 0,
        'show_in_rest'      => true,
        'sanitize_callback' => 'floatval',
        'auth_callback'     => function ( $allowed, $meta_key, $post_id ) {
            return current_user_can( 'edit_post', $post_id );
        },
    ) );
} );
```

| Arg | Notes |
|-----|-------|
| `object_subtype` | Post type or taxonomy; empty means the whole object type |
| `type` | `string`, `boolean`, `integer`, `number`, `array`, `object` |
| `single` | One value vs. array of values |
| `default` | Returned when unset; only honored when `single => true` |
| `sanitize_callback` | `( $value, $key, $object_type, $subtype )` |
| `auth_callback` | Required to expose a protected (`_`) key via REST |
| `show_in_rest` | `true`, or an array with `schema` / `prepare_callback` |
| `revisions_enabled` | Post meta only (6.4+) |

Use `register_post_meta()` / `register_term_meta()` over the generic `register_meta()` — they set the subtype for you.

**Array-typed meta must declare `schema.items`** or REST rejects it:

```php
register_post_meta( 'post', 'myplugin_tags', array(
    'type'         => 'array',
    'single'       => true,
    'show_in_rest' => array(
        'schema' => array(
            'type'  => 'array',
            'items' => array( 'type' => 'string' ),
        ),
    ),
) );
```

Gotchas: register on `init`. A CPT needs `'custom-fields'` in `supports` **and** `show_in_rest => true` for meta to reach the block editor. Registering meta does not prevent `update_post_meta()` from writing unregistered keys — it is not access control.

## Meta boxes

```php
add_action( 'add_meta_boxes', 'myplugin_add_meta_boxes' );

function myplugin_add_meta_boxes() {
    add_meta_box(
        'myplugin_details',                        // id
        __( 'Book Details', 'my-plugin' ),         // title
        'myplugin_render_meta_box',                // render callback
        'myplugin_book',                           // screen (post type)
        'side',                                    // context: normal | side | advanced
        'default'                                  // priority
    );
}

function myplugin_render_meta_box( $post ) {
    wp_nonce_field( 'myplugin_save_meta', 'myplugin_meta_nonce' );

    $isbn = get_post_meta( $post->ID, '_myplugin_isbn', true );
    ?>
    <p>
        <label for="myplugin_isbn"><?php esc_html_e( 'ISBN', 'my-plugin' ); ?></label>
        <input type="text" id="myplugin_isbn" name="myplugin_isbn"
               value="<?php echo esc_attr( $isbn ); ?>" class="widefat">
    </p>
    <?php
}
```

Saving — all four guards are required:

```php
add_action( 'save_post_myplugin_book', 'myplugin_save_meta', 10, 2 );

function myplugin_save_meta( $post_id, $post ) {
    // 1. Skip autosaves and revisions
    if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
        return;
    }
    if ( wp_is_post_revision( $post_id ) ) {
        return;
    }

    // 2. Nonce
    if ( ! isset( $_POST['myplugin_meta_nonce'] )
        || ! wp_verify_nonce( sanitize_key( $_POST['myplugin_meta_nonce'] ), 'myplugin_save_meta' ) ) {
        return;
    }

    // 3. Capability, object-level
    if ( ! current_user_can( 'edit_post', $post_id ) ) {
        return;
    }

    // 4. Sanitize
    $isbn = sanitize_text_field( wp_unslash( $_POST['myplugin_isbn'] ?? '' ) );

    if ( '' === $isbn ) {
        delete_post_meta( $post_id, '_myplugin_isbn' );
    } else {
        update_post_meta( $post_id, '_myplugin_isbn', $isbn );
    }
}
```

`save_post` fires on autosaves, revisions, bulk edits, REST writes, and imports. Without the guards, a quick-edit can wipe meta because the fields were not in the POST.

For the block editor, prefer `register_post_meta()` with `show_in_rest` and a sidebar panel in JS over a classic meta box — classic boxes work but force the editor into compatibility mode.

## Querying by meta

```php
$query = new WP_Query( array(
    'post_type'  => 'myplugin_book',
    'meta_query' => array(
        'relation' => 'AND',
        array(
            'key'     => '_myplugin_price',
            'value'   => 50,
            'compare' => '<=',
            'type'    => 'NUMERIC',
        ),
        array(
            'key'     => '_myplugin_status',
            'value'   => 'available',
            'compare' => '=',
        ),
    ),
) );
```

`compare`: `=`, `!=`, `>`, `>=`, `<`, `<=`, `LIKE`, `NOT LIKE`, `IN`, `NOT IN`, `BETWEEN`, `NOT BETWEEN`, `EXISTS`, `NOT EXISTS`, `REGEXP`.
`type`: `NUMERIC`, `BINARY`, `CHAR`, `DATE`, `DATETIME`, `DECIMAL`, `SIGNED`, `TIME`, `UNSIGNED`.

**`meta_query` does not scale.** `wp_postmeta` has no index on `meta_value`, so each clause is a JOIN plus a full scan. For filtering across many rows, use a taxonomy (indexed) or a custom table. Never use `meta_query` for something a taxonomy models naturally.

Ordering by meta:

```php
'meta_key'  => '_myplugin_price',
'orderby'   => 'meta_value_num',   // meta_value for strings
'order'     => 'ASC',
```

## Front-end output

Meta is user input — escape it:

```php
$isbn = get_post_meta( get_the_ID(), '_myplugin_isbn', true );
if ( $isbn ) {
    printf( '<p>%s %s</p>', esc_html__( 'ISBN:', 'my-plugin' ), esc_html( $isbn ) );
}
```

## Pitfalls

- Forgetting `true` for `$single` — array where a string was expected
- `add_post_meta()` in a loop creating duplicate rows
- Treating `update_post_meta()` returning `false` as an error
- Unprefixed meta keys
- No nonce/capability/autosave guards in the save handler
- `meta_query` on a large table where a taxonomy belongs
- Serializing values manually
- Unescaped meta output
- Expecting `register_meta()` to restrict writes — it does not
