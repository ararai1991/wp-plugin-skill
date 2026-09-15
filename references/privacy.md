# Privacy

If a plugin collects, stores, or transmits personal data, it must give the site owner the means to comply with privacy law. The plugin author is usually the *processor*; the site owner is the *controller*.

## What counts as personal data

Anything identifying a person directly or indirectly: name, email, username, IP address, user agent, geolocation, device fingerprints, order and billing data, comment content and metadata, uploaded media, session identifiers, and any telemetry tied to an individual.

WordPress uses the **email address** as the lookup key, which is why every exporter and eraser callback receives an email rather than a user ID — it covers unregistered users (commenters) too.

## Developer checklist

- What personal data does the plugin collect, and where is it stored?
- Is any of it sent to a third party? Is there explicit opt-in?
- Are exporters and erasers registered?
- Do error logs contain personal data?
- Which capability is required to view it?
- Is it exposed on the front end or through the REST API?
- Is it removed on uninstall, and when a user is deleted?

## Suggested privacy policy content

```php
add_action( 'admin_init', 'myplugin_add_privacy_policy_content' );

function myplugin_add_privacy_policy_content() {
    if ( ! function_exists( 'wp_add_privacy_policy_content' ) ) {
        return;
    }

    $content = sprintf(
        '<p class="privacy-policy-tutorial">%1$s</p><strong class="privacy-policy-tutorial">%2$s</strong> %3$s',
        esc_html__( 'This note is guidance for the site owner and is not copied to the clipboard.', 'my-plugin' ),
        esc_html__( 'Suggested text:', 'my-plugin' ),
        esc_html__( 'When you leave a comment, we store your IP address and browser user agent for 30 days.', 'my-plugin' )
    );

    wp_add_privacy_policy_content(
        __( 'My Plugin', 'my-plugin' ),
        wp_kses_post( wpautop( $content, false ) )
    );
}
```

Must be called on `admin_init` — calling it elsewhere causes problems. Content inside `.privacy-policy-tutorial` appears in the Privacy Policy Guide but is **excluded from the clipboard copy**, so use it for instructions to the site owner, not for policy text.

Cover: why data is collected, whether it is shared, retention period, user rights, where it is stored, and contact information.

## Personal data exporter

```php
add_filter( 'wp_privacy_personal_data_exporters', 'myplugin_register_exporters' );

function myplugin_register_exporters( $exporters ) {
    $exporters['my-plugin'] = array(
        'exporter_friendly_name' => __( 'My Plugin Data', 'my-plugin' ),
        'callback'               => 'myplugin_export_data',
    );
    return $exporters;
}

function myplugin_export_data( $email_address, $page = 1 ) {
    $number = 500;                 // cap per page to avoid timeouts
    $page   = (int) $page;
    $items  = array();

    $records = myplugin_get_records_by_email( $email_address, $number, $page );

    foreach ( $records as $record ) {
        $items[] = array(
            'group_id'    => 'myplugin-records',
            'group_label' => __( 'My Plugin Records', 'my-plugin' ),
            'item_id'     => 'record-' . $record->id,
            'data'        => array(
                array(
                    'name'  => __( 'Submitted On', 'my-plugin' ),
                    'value' => $record->created_at,
                ),
                array(
                    'name'  => __( 'Message', 'my-plugin' ),
                    'value' => $record->message,
                ),
            ),
        );
    }

    return array(
        'data' => $items,
        'done' => count( $records ) < $number,
    );
}
```

Each item needs `group_id` (reuse core's ids like `comments` or `posts` to merge into the same table), `group_label`, `item_id` (unique within the group), and `data` as `name`/`value` pairs.

`done => false` makes core call the callback again with `$page + 1`. A `value` that is a media URL renders as a link. Export ZIPs are cached for 3 days.

## Personal data eraser

```php
add_filter( 'wp_privacy_personal_data_erasers', 'myplugin_register_erasers' );

function myplugin_register_erasers( $erasers ) {
    $erasers['my-plugin'] = array(
        'eraser_friendly_name' => __( 'My Plugin Data', 'my-plugin' ),
        'callback'             => 'myplugin_erase_data',
    );
    return $erasers;
}

function myplugin_erase_data( $email_address, $page = 1 ) {
    $number   = 500;
    $page     = (int) $page;
    $records  = myplugin_get_records_by_email( $email_address, $number, $page );

    $removed  = false;
    $retained = false;
    $messages = array();

    foreach ( $records as $record ) {
        if ( $record->has_invoice ) {
            // Legally required to keep financial records
            $retained   = true;
            $messages[] = __( 'Order records were retained for tax compliance.', 'my-plugin' );
            continue;
        }
        myplugin_delete_record( $record->id );
        $removed = true;
    }

    return array(
        'items_removed'  => $removed,
        'items_retained' => $retained,
        'messages'       => array_unique( $messages ),
        'done'           => count( $records ) < $number,
    );
}
```

| Key | Meaning |
|-----|---------|
| `items_removed` | Data was actually deleted this pass |
| `items_retained` | Some data could not be removed |
| `messages` | Admin-facing explanation — required when `items_retained` is true |
| `done` | `false` re-invokes with the next page |

**Anonymize instead of deleting** when a record must survive:

```php
wp_privacy_anonymize_data( 'email', $email );   // deleted@site.invalid
wp_privacy_anonymize_data( 'ip', $ip );         // 0.0.0.0
// types: email, ip, url, date, text, longtext
```

## Obligations summary

Register exporters (right of access and portability), register erasers (right to erasure), supply privacy policy text (transparency), collect only what you need (minimization), get consent before any telemetry or third-party transmission, delete data in `uninstall.php` and when a user is deleted, gate views behind an appropriate capability, and keep personal data out of logs, REST responses, and front-end output.

## Related

Personal data in error logs is a common leak — see the sensitive data exposure section in `references/security.md`. Cleanup on uninstall is covered in `references/plugin-basics.md`.
