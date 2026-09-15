# WP-Cron

## What it actually is

WP-Cron checks a list of scheduled tasks **on every page load**. It is not a real cron daemon.

If a task is scheduled for 2:00 PM and no page loads happen until 5:00 PM, it runs at 5:00 PM. On a low-traffic site, tasks are late. On a high-traffic site, the check runs constantly.

It also uses **intervals**, not clock times — you give it a first-run timestamp and a repeat interval, not "every hour at 5 past".

The upside: it works on shared hosting without system cron access, and a missed task still runs eventually rather than being abandoned.

## Built-in schedules

`hourly`, `twicedaily`, `daily`, `weekly` (WP 5.4+).

## Custom intervals

```php
add_filter( 'cron_schedules', 'myplugin_cron_schedules' );

function myplugin_cron_schedules( $schedules ) {
    $schedules['myplugin_five_minutes'] = array(
        'interval' => 5 * MINUTE_IN_SECONDS,      // seconds
        'display'  => __( 'Every Five Minutes', 'my-plugin' ),
    );
    return $schedules;
}
```

- **Register the filter on every page load** (file scope or `plugins_loaded`), not only on activation. If the schedule name is unknown when the event fires, the recurring event stops rescheduling itself and silently dies.
- Register it **before** anything calls `wp_schedule_event()` with that name.
- Always return `$schedules`; add keys rather than replacing the array.
- Prefix custom schedule keys.
- Sub-minute intervals are meaningless on a low-traffic site.

## Scheduling

```php
wp_schedule_event( $timestamp, $recurrence, $hook, $args = array(), $wp_error = false );
wp_schedule_single_event( $timestamp, $hook, $args = array(), $wp_error = false );
wp_next_scheduled( $hook, $args = array() );      // timestamp, or false
wp_unschedule_event( $timestamp, $hook, $args = array() );
wp_clear_scheduled_hook( $hook, $args = array() ); // removes ALL occurrences
wp_unschedule_hook( $hook );                       // removes all, regardless of args
wp_get_scheduled_event( $hook, $args = array() );  // full event object (WP 5.1+)
```

## The hook is mandatory

Scheduling stores only a hook name. **You must attach a callback, on every page load**, or the task never runs:

```php
add_action( 'myplugin_daily_task', 'myplugin_do_daily_task' );   // file scope

function myplugin_do_daily_task() {
    // ...
}
```

Forgetting this is the most common reason "my cron doesn't work".

## Always guard against duplicates

`wp_schedule_event()` does **not** deduplicate. Calling it on every page load schedules the task thousands of times.

```php
if ( ! wp_next_scheduled( 'myplugin_daily_task' ) ) {
    wp_schedule_event( time(), 'daily', 'myplugin_daily_task' );
}
```

**Arguments are part of the event's identity.** Cron identity is a hash of hook + args, so:

```php
wp_schedule_event( time(), 'daily', 'myplugin_task', array( 123 ) );

wp_next_scheduled( 'myplugin_task' );              // false — args don't match
wp_next_scheduled( 'myplugin_task', array( 123 ) ); // found
```

Pass the **same args array** to `wp_next_scheduled()`, `wp_unschedule_event()`, and `wp_clear_scheduled_hook()`. Types matter: `'123'` is not `123`.

`wp_schedule_single_event()` deduplicates identical events scheduled within **10 minutes** of each other.

## Lifecycle

Scheduled events persist after deactivation — WordPress keeps trying to run a hook that no longer has a callback. Always clean up.

```php
register_activation_hook( __FILE__, 'myplugin_activate' );

function myplugin_activate() {
    if ( ! wp_next_scheduled( 'myplugin_daily_task' ) ) {
        wp_schedule_event( time(), 'daily', 'myplugin_daily_task' );
    }
}

register_deactivation_hook( __FILE__, 'myplugin_deactivate' );

function myplugin_deactivate() {
    wp_clear_scheduled_hook( 'myplugin_daily_task' );   // handles duplicates, needs no timestamp
}
```

`wp_clear_scheduled_hook()` is the right deactivation cleanup — it removes every occurrence without needing a timestamp.

## Writing cron callbacks

```php
add_action( 'myplugin_daily_task', 'myplugin_do_daily_task' );

function myplugin_do_daily_task() {
    // No request data — cron has no user and no request context
    // Do NOT read $_GET/$_POST, do NOT call current_user_can()

    $items = myplugin_get_pending( 50 );   // process in batches

    foreach ( $items as $item ) {
        myplugin_process( $item );
    }

    // More to do? Reschedule rather than running long
    if ( count( $items ) === 50 ) {
        wp_schedule_single_event( time() + 60, 'myplugin_daily_task' );
    }
}
```

Rules:

- **`wp-cron.php` is publicly reachable** — anyone can trigger a run. Never trust the caller, never read request data.
- **No current user.** `wp_get_current_user()` returns ID 0. Capability checks are meaningless here; if the task acts on behalf of a user, store that user ID in the event args.
- **Make it idempotent.** It may run more than once.
- **Batch.** A long task will hit the PHP time limit and leave work half-done.
- Set a time guard for long jobs rather than assuming completion.

## Real system cron

For reliable timing on a busy or time-sensitive site:

```php
// wp-config.php
define( 'DISABLE_WP_CRON', true );
```

```bash
# Every 5 minutes
*/5 * * * * wget -q -O - https://example.com/wp-cron.php?doing_wp_cron >/dev/null 2>&1

# Or via WP-CLI (preferred — no HTTP overhead)
*/5 * * * * cd /var/www/html && wp cron event run --due-now >/dev/null 2>&1
```

A plugin should not set `DISABLE_WP_CRON` itself — document it as an option for the site owner.

## Testing and inspection

```bash
wp cron event list                    # everything scheduled
wp cron event run myplugin_daily_task # run one now
wp cron event run --due-now
wp cron event delete myplugin_daily_task
wp cron schedule list                 # available intervals
wp cron test                          # is WP-Cron reachable?
```

In code:

```php
$event = wp_get_scheduled_event( 'myplugin_daily_task' );
// ->timestamp, ->schedule, ->interval, ->args

print_r( _get_cron_array() );   // the raw cron option
```

The **WP Crontrol** plugin gives a UI for inspecting, editing, and running events.

## Pitfalls

- **No `add_action()` for the hook** — the task never runs
- **No `wp_next_scheduled()` guard** — thousands of duplicate events
- **Mismatched args** between schedule and unschedule — the event is never found or cleared
- **Registering `cron_schedules` only on activation** — the custom interval is unknown later and the event stops recurring
- **Not clearing events on deactivation**
- **Reading request data or checking capabilities** in a cron callback
- **A long-running task** that hits the time limit
- **Assuming precise timing** — WP-Cron is page-load triggered
- **Scheduling from within the cron callback without a guard** — runaway growth
- Expecting cron to fire on a site with no traffic
