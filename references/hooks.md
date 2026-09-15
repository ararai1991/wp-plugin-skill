# Hooks: Actions and Filters

Hooks are how plugins interact with WordPress. Everything a plugin does happens on a hook.

**Actions** — do something at a point in execution. Return nothing.
**Filters** — modify a value and return it. Must always return.

## Actions

```php
add_action( string $hook, callable $callback, int $priority = 10, int $accepted_args = 1 );
```

```php
add_action( 'init', 'myplugin_init' );
function myplugin_init() {
    register_post_type( 'myplugin_book', array( /* ... */ ) );
}

// With priority and multiple arguments
add_action( 'save_post', 'myplugin_on_save', 10, 3 );
function myplugin_on_save( $post_id, $post, $update ) { /* ... */ }
```

`do_action( 'hook', $arg1, $arg2 )` fires an action.

## Filters

```php
add_filter( string $hook, callable $callback, int $priority = 10, int $accepted_args = 1 );
```

```php
add_filter( 'the_title', 'myplugin_filter_title', 10, 2 );
function myplugin_filter_title( $title, $post_id ) {
    if ( 'myplugin_book' === get_post_type( $post_id ) ) {
        $title = '📖 ' . $title;
    }
    return $title;   // ALWAYS return — a missing return destroys the value
}
```

`apply_filters( 'hook', $value, $arg2 )` applies a filter.

**The single most common filter bug is forgetting to return.** A filter callback that returns nothing sets the value to `null`.

## Priority and argument count

**Priority** (default 10) controls order — lower runs earlier. Same priority runs in registration order. Use `PHP_INT_MAX` to run last, `0` or `1` to run very early. Avoid relying on exotic priorities; if order matters that much, the design is fragile.

**`accepted_args`** must match how many parameters the callback declares. Asking for fewer than you use gives a missing-argument error; the default is 1, which is why multi-argument hooks so often fail silently.

```php
// WRONG — accepted_args defaults to 1, $post and $update are missing
add_action( 'save_post', 'myplugin_save' );
function myplugin_save( $post_id, $post, $update ) {}

// RIGHT
add_action( 'save_post', 'myplugin_save', 10, 3 );
```

## Callback forms

```php
add_action( 'init', 'myplugin_function' );                       // named function
add_action( 'init', array( $this, 'method' ) );                  // instance method
add_action( 'init', array( 'My_Class', 'static_method' ) );      // static method
add_action( 'init', 'My_Class::static_method' );                 // static, string form
add_action( 'init', function () { /* ... */ } );                 // closure
add_action( 'init', __NAMESPACE__ . '\\my_function' );           // namespaced
```

**Closures cannot be removed.** `remove_action()` needs the identical callable, and a closure is a new object each time. Use a named function or method for anything another developer might need to unhook.

## Removing hooks

```php
remove_action( 'hook', 'callback', $priority );   // priority MUST match the original
remove_filter( 'hook', 'callback', $priority );
remove_all_actions( 'hook' );                     // blunt; avoid
```

Timing matters — you can only remove a hook after it was added and before it fires:

```php
// Removing another plugin's hook: wait until it has registered
add_action( 'plugins_loaded', function () {
    remove_action( 'wp_head', 'other_plugin_function', 15 );
}, 20 );
```

For an instance method added by another plugin, you need that object. If it exposes a singleton, `remove_action( 'hook', array( Other_Plugin::instance(), 'method' ) )` works; otherwise find it in `$GLOBALS['wp_filter']`.

## Custom hooks

Make your plugin extensible:

```php
// Action — let others act at a point
do_action( 'myplugin_after_save', $item_id, $data );

// Filter — let others change a value
$price = apply_filters( 'myplugin_item_price', $price, $item_id );

// Filter with a default, for configuration
$per_page = apply_filters( 'myplugin_items_per_page', 20 );
```

Conventions: prefix the hook name, use past tense for "after" actions (`myplugin_item_saved`), pass enough context (IDs and objects) for the callback to be useful, and document each hook with a docblock. Once released, a hook's signature is public API — changing it breaks other people's code.

`do_action_ref_array()` / `apply_filters_ref_array()` pass an array of arguments.

## Essential hooks

**Lifecycle**

| Hook | When |
|------|------|
| `plugins_loaded` | All plugins loaded — earliest safe setup point |
| `init` | Register post types, taxonomies, shortcodes, sessions |
| `wp_loaded` | WordPress fully loaded |
| `admin_init` | Admin-area initialization; settings registration |
| `admin_menu` | Add admin menu pages |
| `wp` | Main query is set up; `$wp_query` available |
| `template_redirect` | Before template loads; good for front-end redirects |
| `shutdown` | End of request |

**Assets**

| Hook | When |
|------|------|
| `wp_enqueue_scripts` | Front-end scripts/styles |
| `admin_enqueue_scripts` | Admin scripts/styles (receives `$hook_suffix`) |
| `login_enqueue_scripts` | Login page |

**Output**

| Hook | When |
|------|------|
| `wp_head` / `wp_footer` | Front-end head/footer output |
| `admin_notices` | Admin notices |
| `the_content` | Filter post content |
| `the_title` | Filter post title |

**Data**

| Hook | When |
|------|------|
| `save_post` | Post saved (fires on autosave and revisions too) |
| `save_post_{post_type}` | Specific post type only |
| `wp_insert_post` | After insert |
| `before_delete_post` / `deleted_post` | Deletion |
| `user_register` / `profile_update` | User changes |
| `pre_get_posts` | Modify the main query before it runs |

**Requests**

| Hook | When |
|------|------|
| `wp_ajax_{action}` | Authenticated AJAX |
| `wp_ajax_nopriv_{action}` | **Unauthenticated** AJAX |
| `rest_api_init` | Register REST routes |
| `admin_post_{action}` | Admin form POST |

## Common patterns

**Guard `save_post`** — it fires on autosaves, revisions, and bulk edits:

```php
add_action( 'save_post_myplugin_book', 'myplugin_save_meta', 10, 2 );

function myplugin_save_meta( $post_id, $post ) {
    if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
        return;
    }
    if ( wp_is_post_revision( $post_id ) ) {
        return;
    }
    if ( ! isset( $_POST['myplugin_nonce'] )
        || ! wp_verify_nonce( sanitize_key( $_POST['myplugin_nonce'] ), 'myplugin_save' ) ) {
        return;
    }
    if ( ! current_user_can( 'edit_post', $post_id ) ) {
        return;
    }

    update_post_meta( $post_id, '_myplugin_isbn',
        sanitize_text_field( wp_unslash( $_POST['isbn'] ?? '' ) ) );
}
```

**Modify the main query** — only the main query, only on the front end:

```php
add_action( 'pre_get_posts', 'myplugin_pre_get_posts' );

function myplugin_pre_get_posts( $query ) {
    if ( is_admin() || ! $query->is_main_query() ) {
        return;
    }
    if ( $query->is_post_type_archive( 'myplugin_book' ) ) {
        $query->set( 'posts_per_page', 12 );
    }
}
```

**Remove your own hook from inside it** — prevents recursion:

```php
add_filter( 'the_content', 'myplugin_content' );
function myplugin_content( $content ) {
    remove_filter( 'the_content', 'myplugin_content' );
    $extra = apply_filters( 'the_content', get_post_meta( get_the_ID(), '_extra', true ) );
    add_filter( 'the_content', 'myplugin_content' );
    return $content . $extra;
}
```

## Inspecting hooks

```php
has_action( 'hook', 'callback' );        // false, or the priority
has_filter( 'hook' );                    // is anything hooked?
did_action( 'init' );                    // how many times it has fired
doing_action( 'save_post' );             // currently firing?
current_filter();                        // name of the running hook
global $wp_filter; print_r( $wp_filter['the_content'] );   // everything on a hook
```

## Pitfalls

- **Forgetting `return` in a filter** — destroys the value.
- **Wrong `accepted_args`** — silent missing arguments.
- **Registering hooks too late.** Adding to `init` from inside `wp_loaded` never fires.
- **Hooking in a constructor that runs on every request** when it only matters in admin.
- **Closures you later need to remove.**
- **`remove_action` with a mismatched priority** — silently does nothing.
- **Infinite recursion** — `update_post_meta()` inside a `save_post` handler that re-triggers the hook.
- **Assuming hook order across plugins.** Priority is not a contract between plugins.
