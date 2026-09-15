# Custom Post Types and Taxonomies

## CPT vs taxonomy vs meta

- **Custom post type** — a content *item* with its own body, author, date, revisions, and permalink: Product, Event, Book, Testimonial.
- **Taxonomy** — a *label that groups* items: Genre, Brand, Color, Region.
- **Post meta** — a value nearly unique per item: price, SKU, ISBN.

Decision heuristics:

- Needs its own title, body, and featured image? → CPT
- Many posts share the value, and users want an archive of everything with it? → taxonomy
- Nearly unique per post? → meta
- Needs fast filtering? → **taxonomy.** `tax_query` uses indexed term tables; `meta_query` scans `wp_postmeta`, which has no index on `meta_value`.

**Anti-pattern:** storing a filterable attribute with a small set of repeating values (Color: red/blue/green) as post meta. It queries slowly and gets no archive page. Make it a taxonomy.

## Registering a post type

```php
add_action( 'init', 'myplugin_register_post_types' );

function myplugin_register_post_types() {
    register_post_type( 'myplugin_book', array(
        'labels'       => array(
            'name'          => __( 'Books', 'my-plugin' ),
            'singular_name' => __( 'Book', 'my-plugin' ),
            'add_new_item'  => __( 'Add New Book', 'my-plugin' ),
            'edit_item'     => __( 'Edit Book', 'my-plugin' ),
            'search_items'  => __( 'Search Books', 'my-plugin' ),
            'not_found'     => __( 'No books found.', 'my-plugin' ),
        ),
        'public'       => true,
        'has_archive'  => true,
        'show_in_rest' => true,                     // REQUIRED for the block editor
        'menu_icon'    => 'dashicons-book',
        'menu_position'=> 20,
        'supports'     => array( 'title', 'editor', 'thumbnail', 'excerpt', 'custom-fields', 'revisions' ),
        'taxonomies'   => array( 'myplugin_genre' ),
        'rewrite'      => array( 'slug' => 'books', 'with_front' => false ),
        'map_meta_cap' => true,
    ) );
}
```

### Key arguments

| Argument | Default | Notes |
|----------|---------|-------|
| `public` | `false` | Master switch; cascades to the flags below |
| `publicly_queryable` | `public` | Front-end queries |
| `show_ui` | `public` | Admin UI |
| `show_in_menu` | `show_ui` | `true`, `false`, or a parent slug like `'tools.php'` |
| `show_in_rest` | `false` | **Required for the block editor** |
| `rest_base` | post type key | REST route segment |
| `hierarchical` | `false` | Parent/child like pages |
| `has_archive` | `false` | `true`, or a string for a custom archive slug |
| `rewrite` | `true` | Array of `slug`, `with_front`, `feeds`, `pages` |
| `supports` | `title`, `editor` | See below |
| `capability_type` | `'post'` | Base for generated capability names |
| `map_meta_cap` | `false` | Enable core's meta-capability mapping |
| `menu_icon` | Posts icon | Dashicons class, URL, or base64 SVG |
| `exclude_from_search` | `! public` | |
| `delete_with_user` | `null` | Delete posts when their author is deleted |

`supports`: `title`, `editor`, `author`, `thumbnail`, `excerpt`, `trackbacks`, `custom-fields`, `comments`, `revisions`, `page-attributes`, `post-formats`.

`custom-fields` is required for meta to reach REST and the block editor. `page-attributes` gives the parent/order box. `supports => false` disables everything, including the title.

### Naming rules

- **Maximum 20 characters** — the `post_type` column is `VARCHAR(20)`; longer keys are silently truncated and break everything.
- Lowercase alphanumerics, dashes, underscores only.
- **Always prefix** — `myplugin_book`, not `book`.
- **Never use `wp_`** — reserved for core.
- Reserved: `post`, `page`, `attachment`, `revision`, `nav_menu_item`, `custom_css`, `customize_changeset`, `oembed_cache`, `user_request`, `wp_block`, `wp_global_styles`, `wp_navigation`, `wp_template`, `wp_template_part`, plus the query terms `action`, `author`, `order`, `theme`.
- **Changing the key later orphans every existing post.** Pick carefully.

## Flushing rewrite rules

Rewrite rules are cached in the `rewrite_rules` option. A new CPT 404s until they regenerate.

**Never call `flush_rewrite_rules()` on `init`** — it rebuilds and re-saves every rule on every request.

```php
// Registration lives in its own function so activation can call it directly
function myplugin_register_post_types() {
    register_post_type( 'myplugin_book', array( 'public' => true ) );
}
add_action( 'init', 'myplugin_register_post_types' );

function myplugin_activate() {
    myplugin_register_post_types();   // init has NOT fired during activation
    flush_rewrite_rules();
}
register_activation_hook( __FILE__, 'myplugin_activate' );

function myplugin_deactivate() {
    unregister_post_type( 'myplugin_book' );
    flush_rewrite_rules();
}
register_deactivation_hook( __FILE__, 'myplugin_deactivate' );
```

Common mistakes:

- **Flushing without registering first** in the activation callback — `init` has not fired, so the rules are built without the CPT.
- `register_activation_hook( __FILE__, ... )` must reference the **main plugin file**. Called from an included file it passes the wrong path and never fires.
- **Activation hooks do not run on update.** If a later version changes a slug, bump a stored version option and flush when it differs.
- Users reporting 404s after you add a CPT usually just need to visit Settings → Permalinks.

## Registering a taxonomy

```php
add_action( 'init', 'myplugin_register_taxonomies' );

function myplugin_register_taxonomies() {
    register_taxonomy( 'myplugin_genre', array( 'myplugin_book' ), array(
        'labels'            => array(
            'name'          => __( 'Genres', 'my-plugin' ),
            'singular_name' => __( 'Genre', 'my-plugin' ),
        ),
        'public'            => true,
        'hierarchical'      => true,      // true = categories, false = tags
        'show_in_rest'      => true,      // required for the block editor
        'show_admin_column' => true,      // column in the post list table
        'rewrite'           => array( 'slug' => 'genre' ),
    ) );
}
```

| Argument | Notes |
|----------|-------|
| `hierarchical` | `true` behaves like categories, `false` like tags |
| `show_in_rest` | Required for the block editor |
| `show_admin_column` | Adds a column to the post list |
| `show_in_quick_edit` | Defaults to `show_ui` |
| `meta_box_cb` | Custom meta box callback, or `false` for none |
| `capabilities` | `manage_terms`, `edit_terms`, `delete_terms`, `assign_terms` |
| `default_term` | Term assigned when none is chosen |
| `rewrite` | `slug`, `with_front`, `hierarchical` |

Taxonomy keys are limited to **32 characters**. Reserved names include `post_tag`, `category`, `nav_menu`, `link_category`, `post_format`, `type`, `taxonomy`, `terms`.

Register taxonomies **before** the post types that use them, or attach them explicitly:

```php
register_taxonomy_for_object_type( 'myplugin_genre', 'myplugin_book' );
```

## Term functions

```php
wp_insert_term( $term, $taxonomy, $args );
wp_set_object_terms( $object_id, $terms, $taxonomy, $append = false );
wp_get_object_terms( $object_ids, $taxonomies, $args );
get_term( $term_id, $taxonomy );
get_terms( array( 'taxonomy' => 'myplugin_genre', 'hide_empty' => false ) );
wp_delete_term( $term_id, $taxonomy );
has_term( $term, $taxonomy, $post_id );
```

`wp_set_object_terms()` with `$append = false` **replaces** all terms — pass `true` to add.

Term meta works like post meta: `add_term_meta()`, `update_term_meta()`, `get_term_meta()`, `delete_term_meta()`.

## Querying

```php
// Posts in a term
$query = new WP_Query( array(
    'post_type' => 'myplugin_book',
    'tax_query' => array(
        array(
            'taxonomy' => 'myplugin_genre',
            'field'    => 'slug',          // term_id | slug | name | term_taxonomy_id
            'terms'    => array( 'fiction', 'mystery' ),
            'operator' => 'IN',            // IN | NOT IN | AND | EXISTS | NOT EXISTS
        ),
    ),
) );

// Terms
$terms = get_terms( array(
    'taxonomy'   => 'myplugin_genre',
    'hide_empty' => false,
    'orderby'    => 'count',
    'order'      => 'DESC',
    'number'     => 10,
) );
```

`get_terms()` returns `WP_Error` on failure — check with `is_wp_error()`.

## Custom capabilities

By default a CPT uses the `post` capabilities, so anyone who can edit posts can edit your CPT. For separate permissions:

```php
register_post_type( 'myplugin_book', array(
    'capability_type' => array( 'book', 'books' ),
    'map_meta_cap'    => true,          // required for edit_post/delete_post to map correctly
    'capabilities'    => array(
        'edit_post'          => 'edit_book',
        'edit_posts'         => 'edit_books',
        'edit_others_posts'  => 'edit_others_books',
        'publish_posts'      => 'publish_books',
        'read_private_posts' => 'read_private_books',
        'delete_post'        => 'delete_book',
    ),
) );
```

Then grant them to roles on activation — see `references/users-roles.md`. Without `map_meta_cap => true`, object-level checks like `current_user_can( 'edit_post', $id )` do not resolve correctly.

## Templates

Front-end template hierarchy for a CPT: `single-{post_type}.php`, `archive-{post_type}.php`, `taxonomy-{taxonomy}.php`, `taxonomy-{taxonomy}-{term}.php`.

A plugin cannot add theme templates directly; use the `template_include` filter to fall back to its own:

```php
add_filter( 'template_include', function ( $template ) {
    if ( is_singular( 'myplugin_book' ) && ! locate_template( 'single-myplugin_book.php' ) ) {
        return MYPLUGIN_DIR . 'templates/single-book.php';
    }
    return $template;
} );
```

## Pitfalls

- CPT key over 20 characters — silently truncated
- Unprefixed key colliding with another plugin
- `show_in_rest => false` then wondering why the block editor won't load
- Flushing rewrite rules on `init`
- Flushing in activation without registering first
- Using post meta for something that should be a taxonomy
- Forgetting `map_meta_cap => true` with custom capabilities
- Changing the post type key after launch — orphans all content
- Registering taxonomies after the post types that reference them
- `wp_set_object_terms()` wiping existing terms because `$append` defaulted to `false`
