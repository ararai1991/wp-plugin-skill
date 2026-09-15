# Testing and Developer Tools

## Debug constants

In `wp-config.php`, **before** `/* That's all, stop editing! */`. Use real booleans — a quoted `'false'` is truthy.

```php
define( 'WP_DEBUG',         true );
define( 'WP_DEBUG_LOG',     true );    // or a path: '/tmp/wp-errors.log'
define( 'WP_DEBUG_DISPLAY', false );
@ini_set( 'display_errors', 0 );
define( 'SCRIPT_DEBUG',     true );    // load unminified core JS/CSS
define( 'SAVEQUERIES',      true );    // record queries in $wpdb->queries
```

| Constant | Effect |
|----------|--------|
| `WP_DEBUG` | Show PHP errors, notices, warnings, deprecations |
| `WP_DEBUG_LOG` | Append to `wp-content/debug.log`; requires `WP_DEBUG` |
| `WP_DEBUG_DISPLAY` | `false` suppresses errors in page HTML |
| `SCRIPT_DEBUG` | Unminified core assets |
| `SAVEQUERIES` | Every query with timing and caller — has real overhead |
| `WP_DISABLE_FATAL_ERROR_HANDLER` | Show the raw fatal instead of recovery mode |

`@ini_set( 'display_errors', 0 )` is needed alongside `WP_DEBUG_DISPLAY` because php.ini may override.

**Never ship these enabled.** `wp-content/debug.log` is publicly readable on many hosts — see the sensitive data exposure section in `references/security.md`.

Your plugin must produce **zero notices** with `WP_DEBUG` on. Undefined index notices are the most common review failure.

## Query Monitor

The single most useful plugin for WordPress development. Shows, per request: database queries grouped by calling plugin, slow queries, hooks and their callbacks, HTTP API requests, REST calls, enqueued scripts and styles, capability checks, template loading, and PHP errors — including for AJAX requests.

Use it to verify your plugin adds no queries to pages where it does nothing.

**Debug Bar** plus add-ons (Console, Cron, Transients, Shortcodes, Actions and Filters) is an alternative with a more granular add-on model.

## Plugin Check (PCP)

The official tool that runs most of the checks the WordPress.org review team uses. **Required to pass Security-category checks for new submissions.**

```bash
wp plugin install plugin-check --activate
wp plugin check my-plugin
wp plugin check my-plugin --categories=security
```

Run it before every release, not just the first.

## WP-CLI

```bash
# Plugin lifecycle
wp plugin list --status=active
wp plugin activate|deactivate|install|update|delete <slug>
wp plugin verify-checksums <slug>          # detect tampering

# Scaffolding
wp scaffold plugin my-plugin --plugin_name="My Plugin" --activate
wp scaffold plugin-tests my-plugin         # PHPUnit harness
wp scaffold post-type my_cpt --plugin=my-plugin
wp scaffold taxonomy my_tax --post_types=my_cpt --plugin=my-plugin

# Cron
wp cron event list
wp cron event run myplugin_daily_task
wp cron event run --due-now
wp cron test

# Database
wp db query "SELECT option_name FROM wp_options WHERE option_name LIKE 'myplugin%'"
wp db export backup.sql
wp db search "myplugin"

# Run code inside a fully loaded WordPress
wp eval 'var_dump( get_option( "myplugin_settings" ) );'
wp eval 'do_action( "myplugin_daily_task" );'
wp eval-file script.php

# Options, transients, users
wp option get myplugin_settings --format=json
wp transient delete --all
wp user create tester tester@example.com --role=editor

# i18n
wp i18n make-pot . languages/my-plugin.pot --domain=my-plugin
wp i18n make-json languages/my-plugin-fr_FR.po --no-purge
```

Useful global flags: `--url=` (multisite), `--user=`, `--skip-plugins=`, `--debug`.

## PHPUnit

```bash
cd wp-content/plugins/my-plugin
wp scaffold plugin-tests my-plugin
bash bin/install-wp-tests.sh wordpress_test root '' localhost latest
phpunit
```

`install-wp-tests.sh` downloads WordPress and the test framework to `/tmp` and **creates the test database, dropping it if it exists** — never point it at a real database.

```php
class Test_MyPlugin_Items extends WP_UnitTestCase {

    public function test_item_is_saved() {
        $post_id = $this->factory->post->create( array( 'post_type' => 'myplugin_book' ) );

        update_post_meta( $post_id, '_myplugin_isbn', '9780000000000' );

        $this->assertSame( '9780000000000', get_post_meta( $post_id, '_myplugin_isbn', true ) );
    }

    public function test_subscriber_cannot_save() {
        $user_id = $this->factory->user->create( array( 'role' => 'subscriber' ) );
        wp_set_current_user( $user_id );

        $this->assertFalse( current_user_can( 'manage_options' ) );
    }

    public function test_invalid_input_returns_error() {
        $result = myplugin_save_item( array( 'title' => '' ) );
        $this->assertWPError( $result );
    }
}
```

`WP_UnitTestCase` wraps each test in a transaction rolled back on teardown, and provides factories (`$this->factory->post|user|term|comment->create()`), `go_to()`, `assertWPError()`, and `assertQueryTrue()`.

**What to test in a plugin:** capability checks reject the wrong role, nonce failures are handled, sanitizers actually sanitize, activation creates what it should, uninstall removes what it should, and every filter returns the right shape.

Mock external HTTP with `pre_http_request`:

```php
add_filter( 'pre_http_request', function () {
    return array( 'body' => '{"ok":true}', 'response' => array( 'code' => 200 ) );
} );
```

## PHPCS with WordPress Coding Standards

```bash
composer require --dev squizlabs/php_codesniffer wp-coding-standards/wpcs \
    dealerdirect/phpcodesniffer-composer-installer

vendor/bin/phpcs
vendor/bin/phpcbf          # auto-fix
```

`phpcs.xml.dist`:

```xml
<?xml version="1.0"?>
<ruleset name="My Plugin">
    <file>.</file>
    <exclude-pattern>/vendor/*</exclude-pattern>
    <exclude-pattern>/node_modules/*</exclude-pattern>

    <rule ref="WordPress"/>
    <rule ref="WordPress.WP.I18n">
        <properties>
            <property name="text_domain" type="array" value="my-plugin"/>
        </properties>
    </rule>
    <config name="minimum_supported_wp_version" value="6.0"/>
    <arg name="extensions" value="php"/>
    <arg value="ps"/>
</ruleset>
```

Standards: `WordPress` (all), `WordPress-Core` (style), `WordPress-Docs`, `WordPress-Extra` (includes `WordPress.Security.*`).

The sniffs that matter most: `WordPress.Security.EscapeOutput`, `WordPress.Security.ValidatedSanitizedInput`, `WordPress.Security.NonceVerification`, `WordPress.DB.PreparedSQL`, `WordPress.WP.I18n`.

Add `PHPCompatibilityWP` to catch syntax unsupported by your minimum PHP version.

## Static analysis

```bash
composer require --dev szepeviktor/phpstan-wordpress
vendor/bin/phpstan analyse --level=5 .

composer require --dev vimeo/psalm humanmade/psalm-plugin-wordpress
vendor/bin/psalm --taint-analysis      # traces input → dangerous sink
```

Psalm's taint analysis is the closest thing to automated vulnerability detection — it follows request data through to SQL, output, and file operations.

## Xdebug

```ini
zend_extension=xdebug
xdebug.mode=debug,develop
xdebug.start_with_request=yes
xdebug.client_host=127.0.0.1
xdebug.client_port=9003
```

`xdebug.mode=develop` alone improves error output and `var_dump` without step-debugging overhead. Add `profile` or `coverage` only when needed — both are slow.

## Manual testing checklist

- Activate and deactivate repeatedly — no errors, no duplicate cron events, no orphaned data
- Test as each role: subscriber, contributor, author, editor, admin
- Try to reach admin pages and AJAX actions **as a subscriber** — they must be rejected
- Submit forms with the nonce removed — must fail
- Multisite: network activate, per-site activate
- `WP_DEBUG` on, zero notices
- With another popular plugin active, and with a default theme
- At the minimum supported WordPress and PHP versions
- Uninstall — verify options, meta, tables, and cron events are gone

## CI

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        php: [ '7.4', '8.2', '8.3' ]
    steps:
      - uses: actions/checkout@v4
      - uses: shivammathur/setup-php@v2
        with:
          php-version: ${{ matrix.php }}
      - run: composer install
      - run: vendor/bin/phpcs
      - run: vendor/bin/phpunit
```

Test the oldest and newest PHP versions you claim to support in `Requires PHP`.
