# Shortcodes

Shortcodes let users place dynamic output inside post content. For new work in the block editor, consider a block instead — but shortcodes remain essential for classic editor support, widgets, and template use.

## Registering

```php
add_action( 'init', 'myplugin_register_shortcodes' );

function myplugin_register_shortcodes() {
    add_shortcode( 'myplugin_books', 'myplugin_books_shortcode' );
}
```

Register on `init`. Always prefix the tag — `[books]` will collide.

## The handler

```php
function myplugin_books_shortcode( $atts, $content = null, $tag = '' ) {
    $atts = shortcode_atts(
        array(
            'count'    => 5,
            'category' => '',
            'orderby'  => 'date',
        ),
        $atts,
        'myplugin_books'   // enables the shortcode_atts_myplugin_books filter
    );

    $count   = absint( $atts['count'] );
    $orderby = in_array( $atts['orderby'], array( 'date', 'title' ), true ) ? $atts['orderby'] : 'date';

    $posts = get_posts( array(
        'post_type'      => 'myplugin_book',
        'posts_per_page' => min( $count, 50 ),
        'orderby'        => $orderby,
        'category_name'  => sanitize_title( $atts['category'] ),
    ) );

    if ( empty( $posts ) ) {
        return '';
    }

    ob_start();
    ?>
    <ul class="myplugin-books">
        <?php foreach ( $posts as $post ) : ?>
            <li>
                <a href="<?php echo esc_url( get_permalink( $post ) ); ?>">
                    <?php echo esc_html( get_the_title( $post ) ); ?>
                </a>
            </li>
        <?php endforeach; ?>
    </ul>
    <?php
    return ob_get_clean();
}
```

**A shortcode must `return`, never `echo`.** Echoed output appears at the top of the page instead of in place, because the shortcode is processed during `the_content` filtering. Use output buffering (`ob_start()` / `ob_get_clean()`) when you want to write markup as HTML rather than build a string.

## Attributes are user input

Anyone who can edit a post can set attributes — including contributors. Attribute values reach your code unsanitized, and unescaped attribute output is one of the most common stored-XSS sources in plugins.

```php
// VULNERABLE
return '<div class="' . $atts['class'] . '">' . $atts['title'] . '</div>';

// CORRECT
return sprintf(
    '<div class="%s">%s</div>',
    esc_attr( $atts['class'] ),
    esc_html( $atts['title'] )
);
```

Normalize keys — WordPress lowercases attribute names but values arrive as typed:

```php
$atts = array_change_key_case( (array) $atts, CASE_LOWER );
```

`shortcode_atts()` only keeps keys present in your defaults array, which is itself a useful allowlist — unknown attributes are discarded.

## Enclosing shortcodes

```php
add_shortcode( 'myplugin_box', function ( $atts, $content = null ) {
    $atts = shortcode_atts( array( 'type' => 'info' ), $atts, 'myplugin_box' );

    $types = array( 'info', 'warning', 'error' );
    $type  = in_array( $atts['type'], $types, true ) ? $atts['type'] : 'info';

    return sprintf(
        '<div class="myplugin-box myplugin-box--%s">%s</div>',
        esc_attr( $type ),
        do_shortcode( wp_kses_post( $content ) )   // process nested shortcodes
    );
} );
```

`[myplugin_box type="warning"]Content here[/myplugin_box]`

`$content` is post content — `wp_kses_post()` is the right filter for it. Call `do_shortcode( $content )` if nested shortcodes should work.

For content that should keep full formatting, run it through the content filters:

```php
$content = apply_filters( 'the_content', $content );
```

Beware recursion if your own shortcode can appear inside itself.

## Conditional asset loading

Do not enqueue on every page. Either detect the shortcode:

```php
add_action( 'wp_enqueue_scripts', function () {
    if ( ! is_singular() ) {
        return;
    }
    $post = get_post();
    if ( $post && has_shortcode( $post->post_content, 'myplugin_books' ) ) {
        wp_enqueue_style( 'myplugin-books', MYPLUGIN_URL . 'css/books.css', array(), MYPLUGIN_VERSION );
    }
} );
```

Or register the asset early and enqueue it from inside the shortcode handler — assets enqueued during `the_content` still make it into the footer:

```php
add_action( 'wp_enqueue_scripts', function () {
    wp_register_style( 'myplugin-books', MYPLUGIN_URL . 'css/books.css', array(), MYPLUGIN_VERSION );
} );

function myplugin_books_shortcode( $atts ) {
    wp_enqueue_style( 'myplugin-books' );   // only when actually rendered
    // ...
}
```

`has_shortcode()` does not find shortcodes inside blocks, widgets, or template parts — the enqueue-from-handler approach is more reliable.

## Other API functions

```php
shortcode_exists( 'myplugin_books' );        // is it registered?
remove_shortcode( 'myplugin_books' );        // unregister
do_shortcode( $string );                     // process shortcodes in a string
strip_shortcodes( $string );                 // remove them (for excerpts)
shortcode_unautop( $content );               // remove <p> wrapping a block-level shortcode
```

In a theme template: `echo do_shortcode( '[myplugin_books count="3"]' );`

Shortcodes are not processed in widgets, excerpts, or comments by default:

```php
add_filter( 'widget_text', 'do_shortcode' );
```

## Pitfalls

- **Echoing instead of returning** — output lands at the top of the page.
- **Unescaped attributes** — stored XSS reachable by any contributor.
- **No `shortcode_atts()`** — missing attributes become undefined-index notices.
- **Unprefixed tag** — collides with other plugins.
- **Unbounded queries** — `count="99999"`; always cap.
- **Enqueuing assets on every page.**
- **Registering outside `init`.**
- **Whitespace/newlines before `return`** inside the handler — breaks `wp_autop` formatting around the output.
- **Assuming `$content` is safe** — it is post content, filter it.
- **Self-closing vs enclosing confusion**: `[tag]` passes `$content = null`; guard before using it.
