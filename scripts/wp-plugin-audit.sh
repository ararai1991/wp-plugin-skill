#!/usr/bin/env bash
# wp-plugin-audit.sh — grep-based security triage for a WordPress plugin.
#
# Usage: ./wp-plugin-audit.sh <plugin-directory>
#
# This is triage, not proof. Every hit needs manual confirmation: check whether
# the code path is reachable, who can reach it, and whether a control exists
# nearby that the grep could not see. Absence of hits is not evidence of safety.
#
# All patterns below are SINGLE-QUOTED. They contain '$' and '\' which the shell
# would otherwise expand or mangle. Do not convert them to double quotes.

set -uo pipefail

DIR="${1:-.}"

if [ ! -d "$DIR" ]; then
    printf 'error: %s is not a directory\n' "$DIR" >&2
    printf 'usage: %s <plugin-directory>\n' "$0" >&2
    exit 1
fi

if command -v rg >/dev/null 2>&1; then
    SEARCH() { rg --no-heading --line-number --color=never -e "$1" -g '*.php' \
                  -g '!vendor/**' -g '!node_modules/**' "$DIR" 2>/dev/null; }
else
    SEARCH() { grep -rnE --include='*.php' --exclude-dir=vendor \
                    --exclude-dir=node_modules -e "$1" "$DIR" 2>/dev/null; }
fi

TOTAL=0
CRIT=0
FUNC=0

section() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }

# check <label> <pattern> [note]
#   label prefixed with "!" marks it a critical security pattern (red)
#   label prefixed with "~" marks it a functionality/correctness finding (blue,
#                                  counted separately from security findings)
check() {
    local label="$1" pattern="$2" note="${3:-}" out n color="1;33" kind="sec"

    case "$label" in
        '!'*) label="${label#!}"; color="1;31"; kind="crit" ;;
        '~'*) label="${label#\~}"; color="1;34"; kind="func" ;;
    esac

    out="$(SEARCH "$pattern")" || true
    [ -z "$out" ] && return 0

    n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

    case "$kind" in
        crit) TOTAL=$((TOTAL + n)); CRIT=$((CRIT + n)) ;;
        func) FUNC=$((FUNC + n)) ;;
        *)    TOTAL=$((TOTAL + n)) ;;
    esac

    printf '\n\033[%sm[%s]\033[0m (%s)\n' "$color" "$label" "$n"
    [ -n "$note" ] && printf '  \033[2m%s\033[0m\n' "$note"
    printf '%s\n' "$out" | head -n 20 | sed 's/^/  /'
    [ "$n" -gt 20 ] && printf '  \033[2m... %s more\033[0m\n' "$((n - 20))"
    return 0
}

# absent <label> <pattern> <note>  — flags when a pattern is NOT found anywhere.
# For checks where the bug is a missing call rather than a present one.
absent() {
    local label="${1#\~}" pattern="$2" note="${3:-}"

    if [ -n "$(SEARCH "$pattern")" ]; then
        return 0
    fi

    FUNC=$((FUNC + 1))
    printf '\n\033[1;34m[%s]\033[0m (missing)\n' "$label"
    [ -n "$note" ] && printf '  \033[2m%s\033[0m\n' "$note"
    return 0
}

# paired <label> <trigger> <required> <note>
# Flags when <trigger> exists in the codebase but <required> does not.
paired() {
    local label="${1#\~}" trigger="$2" required="$3" note="${4:-}" hits n

    hits="$(SEARCH "$trigger")" || true
    [ -z "$hits" ] && return 0
    [ -n "$(SEARCH "$required")" ] && return 0

    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    FUNC=$((FUNC + 1))

    printf '\n\033[1;34m[%s]\033[0m (%s trigger(s), no guard found)\n' "$label" "$n"
    [ -n "$note" ] && printf '  \033[2m%s\033[0m\n' "$note"
    printf '%s\n' "$hits" | head -n 8 | sed 's/^/  /'
    return 0
}

printf '\033[1mWordPress Plugin Audit\033[0m\n'
printf 'Target: %s\n' "$DIR"
printf 'PHP files: %s\n' \
    "$(find "$DIR" -name '*.php' -not -path '*/vendor/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "1. ATTACK SURFACE"

check '!Unauthenticated AJAX (nopriv)' \
    'add_action\(\s*.\s*wp_ajax_nopriv_' \
    'Callable by anyone, no login required. Confirm each is intended to be public.'

check 'Authenticated AJAX handlers' \
    'add_action\(\s*.\s*wp_ajax_[^n]' \
    'Reachable by ANY logged-in user incl. subscribers. Needs capability + nonce.'

check 'REST routes' \
    'register_rest_route' \
    'Each needs a real permission_callback.'

check '!Unauthenticated admin-post' \
    'add_action\(\s*.\s*admin_post_nopriv_' \
    'Public endpoint, no login required.'

check 'admin-post handlers' \
    'add_action\(\s*.\s*admin_post_[^n]' \
    'Needs capability check + check_admin_referer().'

check 'Runs on every request' \
    'add_action\(\s*.\s*(init|wp_loaded|template_redirect|parse_request).\s*,' \
    'If it reads request data and acts on it, it is an unauthenticated entry point.'

check 'Shortcodes / blocks' \
    'add_shortcode|register_block_type' \
    'Attributes are user input — escape at output.'

# ---------------------------------------------------------------------------
section "2. ACCESS CONTROL"

check '!Public REST permission callback' \
    'permission_callback.{0,4}=>\s*.__return_true' \
    'Fully public route. Only valid for public read-only data.'

check '!Arbitrary option write from request' \
    'update_option\(\s*\$_(POST|GET|REQUEST|COOKIE)' \
    'Attacker sets default_role=administrator + users_can_register=1 = site takeover.'

check 'Option name from a variable' \
    '(update_option|delete_option|add_option)\(\s*\$[a-zA-Z_]' \
    'If the option name derives from input, allowlist it.'

check '!User meta key from request' \
    '(update_user_meta|add_user_meta)\(\s*[^,]+,\s*\$_(POST|GET|REQUEST)' \
    'wp_capabilities / wp_user_level writes = privilege escalation.'

check 'User meta writes' \
    '(update_user_meta|add_user_meta|delete_user_meta)\(' \
    'Allowlist the meta keys.'

check 'Role / capability mutation' \
    '(wp_insert_user|wp_update_user|wp_create_user|add_role|->set_role|->add_cap)' \
    'Never accept role, ID, or capabilities from user input.'

check 'Role used as a capability' \
    'current_user_can\(\s*.(administrator|editor|author|contributor|subscriber).' \
    'Check capabilities (manage_options, edit_posts), not role names.'

check 'Direct role array inspection' \
    '->roles|in_array\([^)]*->roles' \
    'Use current_user_can() instead — roles are mutable.'

check 'Auth session manipulation' \
    '(wp_set_auth_cookie|wp_set_current_user|wp_signon)' \
    'Legitimate uses exist, but this is also a backdoor pattern.'

check 'Capability checks present' \
    'current_user_can\(' \
    'Cross-check: one per state-changing handler from section 1?'

# ---------------------------------------------------------------------------
section "3. CSRF"

check '!Nonce result discarded' \
    '^\s*wp_verify_nonce\(' \
    'wp_verify_nonce() RETURNS a value — it must be used in a conditional.'

check 'Nonce verification present' \
    '(check_admin_referer|check_ajax_referer|wp_verify_nonce)' \
    'Cross-check against the state-changing handlers found in section 1.'

# ---------------------------------------------------------------------------
section "4. OUTPUT ESCAPING (XSS)"

check '!Request data echoed directly' \
    '(echo|print)\s+[^;]*\$_(GET|POST|REQUEST|SERVER|COOKIE)' \
    'Reflected XSS.'

check 'Unescaped variable output' \
    '(echo|print)\s+\$[a-zA-Z_]' \
    'Escape by context: esc_html / esc_attr / esc_url / esc_textarea.'

check 'Short echo tags' \
    '<\?=' \
    'Check each for escaping.'

check 'Unescaped translation output' \
    '(^|[^a-z_])(_e|__)\(' \
    'Use esc_html_e() / esc_html__() where output is HTML.'

check 'href/src built from a variable' \
    '(href|src)=.\s*<\?php\s+echo\s+\$' \
    'esc_attr() does NOT block javascript: — use esc_url().'

check 'Unquoted attribute output' \
    '=<\?php\s+echo' \
    'Unquoted attributes are exploitable even when the value is escaped.'

# ---------------------------------------------------------------------------
section "5. SQL INJECTION"

check '!Request data in a wpdb call' \
    '\$wpdb->[a-z_]+\([^)]*\$_(GET|POST|REQUEST|COOKIE)' \
    'Direct SQL injection.'

check '!Interpolation inside prepare()' \
    'prepare\(\s*."[^"]*\$|prepare\(\s*.[^.]*\$\{' \
    'The query argument must be a literal with placeholders — interpolation defeats it.'

check 'Raw wpdb queries' \
    '\$wpdb->(query|get_results|get_row|get_var|get_col)\(' \
    'Any variable in these needs $wpdb->prepare().'

check 'esc_sql() usage' \
    'esc_sql\(' \
    'Not a substitute for prepare() — unsafe outside quoted string contexts.'

check 'Dynamic ORDER BY / LIMIT' \
    '(ORDER BY|LIMIT|GROUP BY)\s+.{0,3}\$' \
    'Identifiers cannot be placeholders — allowlist them.'

# ---------------------------------------------------------------------------
section "6. FILE OPERATIONS"

check '!Raw move_uploaded_file' \
    'move_uploaded_file' \
    'Use wp_handle_upload() with a mimes allowlist + wp_check_filetype_and_ext().'

check 'File upload handling' \
    '\$_FILES' \
    'Never trust $_FILES[..][type] or [name].'

check '!Request data in a file path' \
    '(unlink|file_get_contents|file_put_contents|fopen|readfile|rmdir|scandir|copy|rename)\([^)]*\$_(GET|POST|REQUEST|COOKIE)' \
    'Path traversal to arbitrary file read / write / delete.'

check 'File operations' \
    '(unlink|file_get_contents|file_put_contents|fopen|fwrite|readfile|scandir|glob)\(' \
    'Validate with realpath() + prefix containment check.'

check '!Dynamic include/require' \
    '(include|require)(_once)?\s*\(?\s*\$' \
    'Local file inclusion. Use an allowlist map instead.'

# ---------------------------------------------------------------------------
section "7. DESERIALIZATION & CODE EXECUTION"

check '!unserialize() on request data' \
    '(unserialize|maybe_unserialize)\([^)]*\$_(GET|POST|REQUEST|COOKIE)' \
    'PHP object injection -> POP chain -> RCE.'

check 'Deserialization' \
    '(unserialize|maybe_unserialize)\(' \
    "Prefer json_decode(), or pass ['allowed_classes' => false]."

check '!Code execution sinks' \
    '(^|[^a-z_>$])(eval|assert|create_function)\s*\(' \
    'Almost never legitimate in a plugin.'

check '!Command execution' \
    '(^|[^a-z_>$])(system|exec|shell_exec|passthru|popen|proc_open)\s*\(' \
    'Command injection risk.'

check '!Request data used as a function name' \
    '\$_(GET|POST|REQUEST|COOKIE)\s*\[[^]]*\]\s*\(' \
    'Classic backdoor: request data called as a function.'

check 'Dynamic callables' \
    '(call_user_func|call_user_func_array)\(' \
    'Never let the callback name come from input.'

check 'extract() usage' \
    'extract\(' \
    'Overwrites local scope — dangerous on request data.'

check '!preg_replace /e modifier' \
    'preg_replace\(\s*.[^,]*e[^,]*,' \
    'The /e modifier executes the replacement as PHP code.'

# ---------------------------------------------------------------------------
section "8. SSRF & REDIRECTS"

check 'Remote requests (unsafe variants)' \
    '(wp_remote_get|wp_remote_post|wp_remote_request|wp_remote_head)\(' \
    'Use wp_safe_remote_*() with redirection => 0 when the URL is influenced by input.'

check 'Raw HTTP clients' \
    '(curl_init|curl_exec|fsockopen|stream_context_create)' \
    'Bypasses WordPress SSRF protections entirely.'

check 'Unsafe redirect' \
    'wp_redirect\(' \
    'Use wp_safe_redirect() for input-derived targets; always exit; after.'

check 'Raw Location header' \
    'header\(\s*.Location' \
    'Use wp_safe_redirect().'

check '!TLS verification disabled' \
    'sslverify.{0,4}=>\s*false' \
    'Enables man-in-the-middle.'

# ---------------------------------------------------------------------------
section "9. SECRETS & INFO EXPOSURE"

check '!Possible hardcoded secret' \
    '(api[_-]?key|api[_-]?secret|client[_-]?secret|password|passwd|auth[_-]?token|access[_-]?token)\W{1,4}[=:]\s*.[A-Za-z0-9_/+-]{12,}' \
    'Plugin source is public.'

check 'Debug output' \
    '(var_dump|print_r|var_export|debug_backtrace|phpinfo)\(' \
    'Leaks paths and internals.'

check 'Logging' \
    'error_log\(' \
    'Never log secrets; never write logs inside the webroot.'

check '!Timing-unsafe secret comparison' \
    '(token|secret|signature|hash|key)\s*(==|===)\s*\$' \
    'Use hash_equals().'

# ---------------------------------------------------------------------------
section "10. BACKDOOR INDICATORS"

check 'Encoding / obfuscation functions' \
    '(base64_decode|gzinflate|gzuncompress|str_rot13|hex2bin|convert_uudecode)' \
    'Benign alone; suspicious when nested or feeding an execution sink.'

check '!Nested decoders' \
    '(base64_decode|gzinflate|str_rot13|gzuncompress)\s*\(\s*(base64_decode|gzinflate|str_rot13|gzuncompress)' \
    'Strong backdoor indicator.'

check '!Long encoded blob' \
    '.[A-Za-z0-9+/]{200,}={0,2}.' \
    'Inspect what it decodes to.'

check '!Hex escape chain' \
    '(\\x[0-9a-fA-F]{2}){8,}' \
    'Hidden function names.'

check 'Header-gated activation' \
    '\$_SERVER\[.HTTP_|getallheaders|apache_request_headers' \
    'Conditional-trigger backdoors hide behind custom headers.'

check 'Writes/reads outside the plugin' \
    '(ABSPATH|WP_CONTENT_DIR|WPMU_PLUGIN_DIR|wp-config|wp-includes|mu-plugins|\.htaccess)' \
    'Persistence that survives plugin deletion.'

check '!Hiding from the admin UI' \
    '(pre_current_active_plugins|all_plugins|pre_user_query|views_users|pre_set_site_transient)' \
    'Filters used to conceal plugins, users, or updates.'

check 'Outbound URLs' \
    'https?://[a-zA-Z0-9.-]+' \
    'Review any domain unrelated to the vendor.'

# ---------------------------------------------------------------------------
section "11. CORRECTNESS — LIFECYCLE"

paired '~CPT/taxonomy without rewrite flush' \
    'register_post_type\(|register_taxonomy\(' \
    'flush_rewrite_rules' \
    'Permalinks 404 until rules are regenerated. Call the registration function then flush_rewrite_rules() in register_activation_hook.'

# flush_rewrite_rules() is correct only in activation/deactivation. Flag every
# call site; the note tells the reviewer what to confirm. (A single-line grep
# cannot see which function body a call sits in.)
check '~flush_rewrite_rules call sites' \
    'flush_rewrite_rules\s*\(' \
    'Correct ONLY inside activation/deactivation. On init or any per-request hook it rebuilds every rule on every page load.'

paired '~Scheduled events never cleared' \
    'wp_schedule_event\(|wp_schedule_single_event\(' \
    'wp_clear_scheduled_hook|wp_unschedule_event|wp_unschedule_hook' \
    'Events keep firing after deactivation. Clear them in register_deactivation_hook.'

paired '~wp_schedule_event without duplicate guard' \
    'wp_schedule_event\(' \
    'wp_next_scheduled' \
    'Without a wp_next_scheduled() guard the event is scheduled again on every run.'

paired '~cron_schedules filter missing' \
    'wp_schedule_event\([^)]*,\s*.(myplugin|wporg|[a-z_]*_)(five|ten|fifteen|thirty|every)' \
    'cron_schedules' \
    'A custom interval name needs the cron_schedules filter registered on every page load, or the event stops recurring.'

paired '~Activation hook without deactivation' \
    'register_activation_hook' \
    'register_deactivation_hook' \
    'State created on activation is usually not cleaned up.'

paired '~No uninstall cleanup' \
    'add_option\(|update_option\(' \
    'uninstall\.php|register_uninstall_hook|WP_UNINSTALL_PLUGIN' \
    'Plugin stores options but has no uninstall routine — data is orphaned on delete.'

check '~Lifecycle hook using a non-__FILE__ path' \
    'register_(activation|deactivation|uninstall)_hook\(\s*[^_ )][^,)]*,' \
    'These need the MAIN plugin file path. A constant or variable here is often wrong, and __FILE__ from an included file never fires.'

# ---------------------------------------------------------------------------
section "12. CORRECTNESS — API USAGE"

check '~add_role / remove_role call sites' \
    '(^|[^_>a-z])(add_role|remove_role)\s*\(' \
    'These write to the DB and add_role() is a NO-OP if the role exists. Correct only on activation/deactivation; editing the caps array later changes nothing on existing sites without a version migration.'

check '~register_post_type without show_in_rest' \
    'register_post_type\(' \
    'Verify each has show_in_rest => true, or the block editor will not load for it.'

check '~Meta registered without show_in_rest' \
    'register_(post_)?meta\(' \
    'Meta needs show_in_rest (and custom-fields in the CPT supports array) to reach the block editor.'

check '~get_*_meta without $single, result used as a scalar' \
    '(echo|print|esc_\w+|=\s*)\s*get_(post|user|term|comment)_meta\(\s*[^,]+,\s*[^,)]+\s*\)' \
    'Third arg omitted returns an ARRAY, not the value — "Array to string conversion".'

check '~add_*_meta without $unique' \
    'add_(post|user|term|comment)_meta\(\s*[^,]+,\s*[^,]+,\s*[^,)]+\s*\)\s*;' \
    '$unique defaults to false, so each call APPENDS another row. Use update_*_meta for single-value fields.'

check '~wp_set_object_terms without $append' \
    'wp_set_object_terms\(\s*[^,]+,\s*[^,]+,\s*[^,)]+\s*\)' \
    '$append defaults to false, which REPLACES all existing terms.'

check '~set_role where add_role may be meant' \
    '->set_role\(' \
    'set_role() removes every other role from the user.'

# Inline single-line filter closures that contain no 'return' — a real bug,
# unlike flagging every add_filter() call.
FILTER_NORETURN="$( SEARCH 'add_filter\([^)]*function\s*\([^)]*\)\s*\{[^}]*\}' | grep -vE 'return' || true )"
if [ -n "$FILTER_NORETURN" ]; then
    n="$( printf '%s\n' "$FILTER_NORETURN" | wc -l | tr -d ' ' )"
    FUNC=$(( FUNC + n ))
    printf '\n\033[1;34m[%s]\033[0m (%s)\n' 'Filter closure with no return' "$n"
    printf '  \033[2m%s\033[0m\n' 'A filter callback that returns nothing sets the filtered value to null.'
    printf '%s\n' "$FILTER_NORETURN" | head -n 20 | sed 's/^/  /'
fi

check '~Multi-arg hook without accepted_args' \
    "add_(action|filter)\(\s*.(save_post|profile_update|user_register|wp_insert_post|transition_post_status|comment_post).\s*,\s*[^,]+\s*\)" \
    'These hooks pass 2-4 args; accepted_args defaults to 1, so extra params arrive as missing-argument errors.'

paired '~save_post without autosave guard' \
    "add_action\(\s*.save_post" \
    'DOING_AUTOSAVE|wp_is_post_revision|wp_is_post_autosave' \
    'save_post fires on autosaves, revisions and bulk edits — unguarded handlers wipe meta.'

check '~Direct SQL where a core API exists' \
    '\$wpdb->(get_results|get_row|query)\([^)]*(wp_posts|wp_postmeta|wp_users|wp_options|\{\$wpdb->(posts|postmeta|users|options)\})' \
    'Prefer WP_Query / get_posts / get_option — they handle caching and hooks.'

check '~Unbounded query' \
    "('posts_per_page'|'numberposts'|'number')\s*=>\s*-1" \
    'Loads every row into memory; breaks as the site grows.'

check '~Autoloaded option (verify size)' \
    'add_option\(\s*[^,]+,\s*[^,]+\s*\)' \
    'Autoloads by default and is read on EVERY request. Pass \x27no\x27 for large or rarely-read values.'

# ---------------------------------------------------------------------------
section "13. CORRECTNESS — I18N & OUTPUT"

check '~Variable or constant as text domain' \
    "(__|_e|_x|_n|esc_html__|esc_html_e|esc_attr__)\([^)]*,\s*\\\$[a-zA-Z_]" \
    'The text domain must be a literal string — a variable means no strings are extracted.'

check '~Interpolated variable in a translated string' \
    '(__|_e|esc_html__|esc_html_e)\(\s*"[^"]*\$' \
    'Variables must be printf placeholders, not interpolated — the extracted string never matches at runtime.'

check '~Unnumbered placeholders with multiple args' \
    '(printf|sprintf)\(\s*[^,]*%s[^,]*%s' \
    'Use %1$s / %2$s so translators can reorder them.'

check '~Shortcode handlers — verify' \
    'add_shortcode\(' \
    'Each handler must RETURN (never echo), use shortcode_atts() for defaults, and escape every attribute at output.'

paired '~Shortcodes without shortcode_atts anywhere' \
    'add_shortcode\(' \
    'shortcode_atts' \
    'No shortcode_atts() call found — missing attributes will raise undefined-index notices.'

# ---------------------------------------------------------------------------
section "14. HYGIENE"

printf '\n\033[1;33m[Files missing ABSPATH guard]\033[0m\n'
MISSING=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! grep -q 'ABSPATH' "$f" 2>/dev/null; then
        printf '  %s\n' "$f"
        MISSING=$((MISSING + 1))
    fi
done < <(find "$DIR" -name '*.php' -not -path '*/vendor/*' -not -path '*/node_modules/*' 2>/dev/null)
if [ "$MISSING" -eq 0 ]; then printf '  \033[32mnone\033[0m\n'; else TOTAL=$((TOTAL + MISSING)); fi

printf '\n\033[1;33m[Abnormally long lines]\033[0m \033[2m(possible obfuscation)\033[0m\n'
LONG="$(find "$DIR" -name '*.php' -not -path '*/vendor/*' -not -path '*/node_modules/*' \
        -exec awk 'length > 1000 {print FILENAME":"FNR" ("length" chars)"}' {} \; 2>/dev/null)"
if [ -n "$LONG" ]; then printf '%s\n' "$LONG" | head -n 10 | sed 's/^/  /'; else printf '  \033[32mnone\033[0m\n'; fi

printf '\n\033[1;33m[PHP files in asset directories]\033[0m\n'
ASSETPHP="$(find "$DIR" \( -path '*/uploads/*' -o -path '*/images/*' -o -path '*/img/*' \
            -o -path '*/css/*' -o -path '*/js/*' -o -path '*/fonts/*' \) -name '*.php' 2>/dev/null)"
if [ -n "$ASSETPHP" ]; then printf '%s\n' "$ASSETPHP" | sed 's/^/  /'; else printf '  \033[32mnone\033[0m\n'; fi

# ---------------------------------------------------------------------------
printf '\n\033[1;36m=== SUMMARY ===\033[0m\n'
printf '\033[1;33mSecurity\033[0m       %s flagged  (\033[1;31m%s critical-pattern hits\033[0m)\n' "$TOTAL" "$CRIT"
printf '\033[1;34mFunctionality\033[0m  %s flagged\n' "$FUNC"
cat <<'EOF'

Triage signals, not confirmed defects.

Security hits — for each, ask:
  1. Is the code path reachable from an HTTP request?
  2. Who can reach it — unauthenticated, subscriber, or admin?
  3. Is there a capability check AND a nonce check before the side effect?
  4. Is input sanitized and output escaped for its context?

Functionality hits — many are "verify this" prompts rather than definite bugs.
Several are whole-codebase checks (a missing flush, no deactivation cleanup),
so one line of output can mean the guard is absent everywhere, not at that spot.

Then run the real tools:
  wp plugin check <slug> --categories=security
  phpcs --standard=WordPress-Extra --extensions=php <dir>
  phpstan analyse --level=5 <dir>
  psalm --taint-analysis
EOF
