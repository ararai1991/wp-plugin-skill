# Users, Roles, and Capabilities

A **role** is a named bundle of **capabilities**. Users get roles; code checks capabilities.

**Always check capabilities, never role names.** Roles are mutable, sites add custom roles, and multiple roles can hold the same capability.

```php
current_user_can( 'manage_options' );        // correct
current_user_can( 'administrator' );         // WRONG — a role is not a capability
in_array( 'editor', $user->roles, true );    // WRONG — fragile and incomplete
```

## Default roles

| Role | Summary |
|------|---------|
| Super Admin | Multisite network control |
| Administrator | Everything on a single site |
| Editor | Publish and manage all posts, including others' |
| Author | Publish and manage their own posts; can upload |
| Contributor | Write own posts, cannot publish, **no `upload_files`** |
| Subscriber | `read` only |

Key capabilities by tier:

- **Subscriber**: `read`
- **Contributor**: + `edit_posts`, `delete_posts`
- **Author**: + `publish_posts`, `upload_files`, `edit_published_posts`, `delete_published_posts`
- **Editor**: + `edit_others_posts`, `delete_others_posts`, `edit_pages`, `publish_pages`, `manage_categories`, `moderate_comments`, `read_private_posts`, `unfiltered_html`
- **Administrator**: + `manage_options`, `activate_plugins`, `edit_theme_options`, `list_users`, `promote_users`, `remove_users`, `export`, `import`, `switch_themes`

On **single-site only**, administrators also get `install_plugins`, `update_plugins`, `delete_plugins`, `edit_plugins`, `install_themes`, `update_themes`, `edit_users`, `create_users`, `delete_users`, `update_core`, `unfiltered_html`. On multisite these belong to Super Admins alone — so a plugin gating on `install_plugins` behaves differently on multisite.

`unfiltered_upload` is granted to **no role** by default and requires `ALLOW_UNFILTERED_UPLOADS` in `wp-config.php`.

## Choosing the right capability

| Action | Capability |
|--------|------------|
| Plugin settings page | `manage_options` |
| Editing content | `edit_posts` |
| Editing a specific post | `edit_post` with the post ID |
| Uploading | `upload_files` |
| Managing users | `edit_users` / `list_users` |
| Managing terms | `manage_categories` |
| Viewing private content | `read_private_posts` |

Use the **least** capability that fits. `manage_options` on a feature editors should use locks them out.

## Checking capabilities

```php
current_user_can( $capability, ...$args );
user_can( $user_or_id, $capability, ...$args );
author_can( $post, $capability, ...$args );
current_user_can_for_blog( $blog_id, $capability, ...$args );
```

**Object-level (meta) capabilities** take the object ID and are what you want for per-item checks:

```php
current_user_can( 'edit_post', $post_id );      // not just edit_posts
current_user_can( 'delete_post', $post_id );
current_user_can( 'edit_user', $user_id );
current_user_can( 'edit_term', $term_id );
```

`edit_posts` means "can edit posts in general". `edit_post` with an ID means "can edit *this* post" — it accounts for authorship, post status, and lock state. Using the plural form for a specific object is an IDOR bug.

## Custom roles — the persistence gotcha

Roles live in the `wp_user_roles` **database option**, not in code.

**`add_role()` is a no-op if the role already exists.** Editing the capability array in your source changes nothing on a site where the role was already created. This surprises nearly everyone.

```php
// WRONG — writes to the DB on every request, and silently ignores later changes
add_action( 'init', function () {
    add_role( 'myplugin_manager', 'Manager', array( 'read' => true ) );
} );
```

```php
// RIGHT — create on activation, clean up on deactivation
register_activation_hook( __FILE__, 'myplugin_activate' );

function myplugin_activate() {
    add_role( 'myplugin_manager', __( 'Product Manager', 'my-plugin' ), array(
        'read'                     => true,
        'upload_files'             => true,
        'edit_myplugin_products'   => true,
        'publish_myplugin_products'=> true,
    ) );

    $admin = get_role( 'administrator' );
    if ( $admin ) {
        $admin->add_cap( 'edit_myplugin_products' );
        $admin->add_cap( 'publish_myplugin_products' );
    }
}

register_deactivation_hook( __FILE__, 'myplugin_deactivate' );

function myplugin_deactivate() {
    remove_role( 'myplugin_manager' );

    $admin = get_role( 'administrator' );
    if ( $admin ) {
        $admin->remove_cap( 'edit_myplugin_products' );
        $admin->remove_cap( 'publish_myplugin_products' );
    }
}
```

To change capabilities in a later version, store a version option and migrate — activation hooks do not run on update:

```php
add_action( 'plugins_loaded', function () {
    if ( get_option( 'myplugin_roles_version' ) !== MYPLUGIN_ROLES_VERSION ) {
        myplugin_update_roles();
        update_option( 'myplugin_roles_version', MYPLUGIN_ROLES_VERSION );
    }
} );
```

`remove_cap()` is equally persistent — removing a core capability stays removed even after deactivation unless you restore it. Never remove the Administrator role. If you remove Subscriber, update `default_role` too, and reassign users who held a removed role or they lose access entirely.

## Modifying roles

```php
$role = get_role( 'editor' );
$role->add_cap( 'myplugin_manage' );
$role->remove_cap( 'myplugin_manage' );
$role->has_cap( 'edit_posts' );
```

Per-user:

```php
$user = new WP_User( $user_id );
$user->add_role( 'editor' );
$user->remove_role( 'editor' );
$user->set_role( 'editor' );        // replaces ALL roles
$user->add_cap( 'myplugin_special' );
```

`set_role()` wipes every other role — use `add_role()` for multi-role users.

## Custom capabilities for a CPT

```php
register_post_type( 'myplugin_product', array(
    'capability_type' => array( 'product', 'products' ),
    'map_meta_cap'    => true,      // required for edit_post/delete_post to resolve
) );
```

That generates `edit_product`, `edit_products`, `edit_others_products`, `publish_products`, `read_private_products`, `delete_product`, and so on. Grant them to roles on activation, as above. Without `map_meta_cap => true`, object-level checks do not map correctly.

## User meta

```php
update_user_meta( $user_id, 'myplugin_phone', $value );
get_user_meta( $user_id, 'myplugin_phone', true );
delete_user_meta( $user_id, 'myplugin_phone' );
```

**Never write a user-controlled meta key.** `wp_capabilities` and `wp_user_level` are role storage — allowing arbitrary keys is privilege escalation:

```php
// VULNERABLE
foreach ( $_POST['meta'] as $key => $value ) {
    update_user_meta( $user_id, $key, $value );
}

// CORRECT — allowlist
$allowed = array( 'myplugin_phone', 'myplugin_company' );
foreach ( (array) $_POST['meta'] as $key => $value ) {
    $key = sanitize_key( $key );
    if ( in_array( $key, $allowed, true ) ) {
        update_user_meta( $user_id, $key, sanitize_text_field( wp_unslash( $value ) ) );
    }
}
```

## Creating and updating users

```php
$user_id = wp_insert_user( array(
    'user_login' => sanitize_user( $login ),
    'user_email' => sanitize_email( $email ),
    'user_pass'  => $password,            // hashed automatically
    'role'       => 'subscriber',         // NEVER from user input
) );

if ( is_wp_error( $user_id ) ) {
    return $user_id;
}
```

**Never pass a user-supplied `role` or `ID`.** A user-controlled `ID` turns "create user" into "overwrite an existing user, including an administrator" — a classic privilege escalation. Never accept `user_pass` pre-hashed from a request.

`wp_create_user( $login, $password, $email )` is a thin wrapper. `wp_update_user()` takes the same array plus `ID`.

## Current user

```php
$user = wp_get_current_user();          // WP_User; ID 0 when logged out
$id   = get_current_user_id();          // 0 when logged out
is_user_logged_in();
```

`wp_get_current_user()` is unreliable before `init` — the user is not set up yet.

## Querying users

```php
$query = new WP_User_Query( array(
    'role'       => 'myplugin_manager',
    'role__in'   => array( 'editor', 'author' ),
    'meta_key'   => 'myplugin_active',
    'meta_value' => '1',
    'number'     => 20,
    'paged'      => 1,
    'orderby'    => 'registered',
    'fields'     => array( 'ID', 'user_email' ),   // limit columns
) );

foreach ( $query->get_results() as $user ) { /* ... */ }
```

`get_users( $args )` is a convenience wrapper. Avoid unbounded user queries on large sites, and never expose emails without a capability check on the reader.

## Authentication hooks

| Hook | Use |
|------|-----|
| `wp_login` | After successful login (`$user_login`, `$user`) |
| `wp_logout` | On logout |
| `wp_login_failed` | Failed attempt |
| `authenticate` | Filter — add checks or block login |
| `user_register` | New user created |
| `profile_update` | User updated |
| `delete_user` / `deleted_user` | Before/after deletion |
| `set_auth_cookie` | Auth cookie set |

```php
add_filter( 'authenticate', function ( $user, $username ) {
    if ( $user instanceof WP_User && myplugin_is_blocked( $user->ID ) ) {
        return new WP_Error( 'blocked', __( 'This account is suspended.', 'my-plugin' ) );
    }
    return $user;
}, 30, 2 );
```

Clean up plugin data on `delete_user` — see `references/privacy.md`.

## Pitfalls

- Checking a role instead of a capability
- `edit_posts` where `edit_post` with an ID is needed — IDOR
- Expecting `add_role()` to update an existing role
- Running `add_role()` on `init` instead of activation
- Removing core capabilities and not restoring them on deactivation
- User-controlled meta keys or `role` values — privilege escalation
- Passing a user-supplied `ID` to `wp_insert_user()`
- `set_role()` where `add_role()` was intended
- Assuming administrators have `install_plugins` on multisite
- Calling `wp_get_current_user()` before `init`
