# Backdoor and Supply-Chain Indicators

Use when reviewing a third-party plugin, a plugin after an ownership change, or a site suspected of compromise. WordPress plugin supply-chain attacks are real and recurring: attackers compromise a developer account, ship a signed-looking update, and leave the payload dormant so the plugin's reputation matures before activation.

## Why static scanning misses these

Modern planted backdoors are conditional. The malicious path only executes when a specific HTTP header, cookie, user agent, or query parameter is present — so a scanner that never sends that trigger never sees the behavior. Signature detection also fails on novel code from a publisher with a clean history. That makes manual review of *code shape* more reliable than looking for known strings.

## Execution sinks — input reaching code execution

The core pattern is almost always request data flowing into a code-execution function:

```php
// Variations of the same backdoor
eval( base64_decode( $_POST['x'] ) );
assert( $_GET['c'] );
$f = 'system'; $f( $_REQUEST['cmd'] );
call_user_func( $_GET['f'], $_GET['a'] );
preg_replace( '/.*/e', $_POST['c'], '' );
create_function( '', $_POST['c'] );
${'_'.'GET'}['x']( ${'_'.'GET'}['y'] );
$_GET['a']( $_GET['b'] );                 // dynamic call, no literal function name
```

```bash
grep -rnE "\b(eval|assert|create_function|system|exec|shell_exec|passthru|popen|proc_open)\b" --include=*.php .
grep -rnE "\\\$_(GET|POST|REQUEST|COOKIE|SERVER)\s*\[[^]]*\]\s*\(" --include=*.php .
grep -rn "call_user_func\|call_user_func_array\|array_map( *\$" --include=*.php .
```

## Obfuscation and encoding

```bash
grep -rnE "base64_decode|gzinflate|gzuncompress|str_rot13|hex2bin|pack\(|convert_uu" --include=*.php .

# Nested decoders — a strong signal
grep -rnE "(base64_decode|gzinflate|str_rot13)\s*\(\s*(base64_decode|gzinflate|str_rot13)" --include=*.php .

# Long encoded blobs
grep -rnE "['\"][A-Za-z0-9+/]{200,}={0,2}['\"]" --include=*.php .

# Hex/octal escape chains used to hide function names
grep -rnE "(\\\\x[0-9a-fA-F]{2}){8,}" --include=*.php .

# Character-code assembly
grep -rn "chr( *[0-9]\+ *)\s*\.\s*chr(" --include=*.php .
```

`base64_decode` alone is not proof — legitimate plugins encode images and API payloads. Nested decoders, decoded output reaching an execution sink, or a blob with no clear purpose are the real signals.

## Conditional activation triggers

Look for behavior that only fires under attacker-chosen conditions:

```bash
grep -rn "\$_SERVER\['HTTP_" --include=*.php .          # custom header triggers
grep -rn "getallheaders\|apache_request_headers" --include=*.php .
grep -rn "\$_COOKIE\[" --include=*.php .                 # cookie-gated activation
grep -rn "HTTP_USER_AGENT" --include=*.php .             # UA-gated activation
grep -rn "REMOTE_ADDR" --include=*.php .                 # attacker-IP allowlist
```

Also look for hardcoded comparison values — a magic string compared against a header or parameter is the classic activation gate.

## Hidden accounts and privilege grants

```bash
grep -rn "wp_insert_user\|wp_create_user\|add_role\|set_role\|add_cap\|wp_set_current_user" --include=*.php .
grep -rn "users_can_register\|default_role" --include=*.php .
grep -rn "wp_set_auth_cookie\|wp_signon" --include=*.php .
```

A plugin creating a user, granting a capability, or setting an auth cookie outside a documented feature is a backdoor. Watch for code that hides a user from the admin user list (filtering `pre_user_query`, `views_users`, or the user count).

## Callback to external infrastructure

```bash
grep -rn "wp_remote_\|curl_init\|file_get_contents( *['\"]http\|fsockopen\|stream_context_create" --include=*.php .
grep -rnE "https?://[a-zA-Z0-9.-]+" --include=*.php . | grep -v "wordpress.org\|w3.org\|schema.org"
```

Red flags: reporting site URL/admin email to an unfamiliar domain on activation; fetching code and executing it; hardcoded IPs; domains unrelated to the vendor; pastebin/raw-gist URLs.

## Persistence mechanisms

Backdoors survive plugin deletion by writing outside the plugin directory:

```bash
# Writes outside the plugin's own folder
grep -rn "file_put_contents\|fwrite\|fputs\|copy(\|rename(" --include=*.php .
grep -rn "ABSPATH\|WP_CONTENT_DIR\|wp-includes\|wp-config\|\.htaccess" --include=*.php .

# Scheduled re-infection
grep -rn "wp_schedule_event\|wp_schedule_single_event" --include=*.php .

# Must-use plugin drop (auto-loads, not listed normally)
grep -rn "WPMU_PLUGIN_DIR\|mu-plugins" --include=*.php .

# Autoloaded option payloads
grep -rn "add_option(.*'yes'\|update_option(.*autoload" --include=*.php .
```

On a compromised site, also check directly: `wp-includes/vars.php`, `wp-config.php` tails, `wp-content/mu-plugins/`, `.htaccess`, any recently modified core file, and autoloaded `wp_options` rows containing `eval`, `base64`, or external URLs.

## Hiding from the admin

```bash
grep -rn "pre_current_active_plugins\|all_plugins\|plugin_action_links" --include=*.php .
grep -rn "pre_user_query\|views_users\|users_list_table" --include=*.php .
grep -rn "site_transient_update_plugins\|pre_set_site_transient" --include=*.php .
```

Filters that remove a plugin from the plugin list, remove a user from the user list, or suppress update notices are unambiguous indicators.

## File-level heuristics

- A PHP file with abnormally long single lines, or one line of thousands of characters
- Files with misleading names (`wp-cache.php`, `class-wp-db.php`) in the plugin folder
- PHP inside `uploads/`, or in an `images/`/`css/`/`js/` directory
- Double extensions: `logo.php.png`, `data.jpg.php`
- Files whose modification time is far off from the rest of the plugin
- Trailing code after a long run of blank lines — pushed past where a reviewer scrolls
- Comment headers claiming to be from a different, legitimate plugin

```bash
find . -name "*.php" -exec awk 'length > 1000 {print FILENAME": line "FNR" ("length" chars)"}' {} \;
find ./uploads ./assets ./images ./css ./js -name "*.php" 2>/dev/null
find . -name "*.php" -newermt "$(date -d '7 days ago' +%Y-%m-%d)" 2>/dev/null
```

## Verifying integrity of a released plugin

```bash
# Compare a directory against the official WordPress.org release
wp plugin verify-checksums <slug>
wp plugin verify-checksums --all

# Or diff the installed copy against a fresh download of the same version
```

An unexplained difference between an installed plugin and its official release is a compromise until proven otherwise.

## If you find one

1. Do not merely delete the plugin — persistence commonly lives in `mu-plugins`, `wp-config.php`, core files, cron, or database options.
2. Assume credential compromise: rotate all admin passwords, database credentials, API keys, and salts in `wp-config.php`.
3. Audit users for accounts created or elevated since the plugin was installed.
4. Inspect scheduled events (`wp cron event list`) and autoloaded options.
5. Verify core file integrity (`wp core verify-checksums`).
6. Restore from a backup predating the compromise where possible; otherwise rebuild.
7. Report the plugin to `plugins@wordpress.org` and to Wordfence/Patchstack.
