# Abilities API and AI Client

Two new core APIs change how plugins expose actions and use language models:

- **Abilities API** (WordPress 6.9+) — register named, schema-described actions that REST clients, MCP servers, and AI agents can discover and execute.
- **AI Client + Connectors** (WordPress 7.0+) — a provider-agnostic `wp_ai_client_prompt()` for calling an LLM, with API keys managed centrally under Settings → Connectors.

Both are new attack surface. An ability is an endpoint that an *AI agent* may call on a user's behalf, and model output is attacker-influenced text. Apply the three gates exactly as you would to a REST route.

Guard for older installs:

```php
if ( function_exists( 'wp_register_ability' ) ) { /* 6.9+ */ }
if ( function_exists( 'wp_ai_client_prompt' ) ) { /* 7.0+ */ }
```

---

## Abilities API

### Registering

Categories register on `wp_abilities_api_categories_init`; abilities register on `wp_abilities_api_init`. A category must exist before an ability references it.

```php
add_action( 'wp_abilities_api_categories_init', function () {
    wp_register_ability_category( 'my-plugin-catalog', array(
        'label'       => __( 'Book Catalog', 'my-plugin' ),
        'description' => __( 'Read and manage books in the catalog.', 'my-plugin' ),
    ) );
} );

add_action( 'wp_abilities_api_init', 'myplugin_register_abilities' );

function myplugin_register_abilities() {
    wp_register_ability( 'my-plugin/get-book', array(
        'label'               => __( 'Get Book', 'my-plugin' ),
        'description'         => __( 'Returns a book by ID, including title, ISBN and genre.', 'my-plugin' ),
        'category'            => 'my-plugin-catalog',
        'input_schema'        => array(
            'type'       => 'object',
            'properties' => array(
                'id' => array( 'type' => 'integer', 'minimum' => 1 ),
            ),
            'required'   => array( 'id' ),
            'additionalProperties' => false,
        ),
        'output_schema'       => array(
            'type'       => 'object',
            'properties' => array(
                'id'    => array( 'type' => 'integer' ),
                'title' => array( 'type' => 'string' ),
                'isbn'  => array( 'type' => 'string' ),
            ),
        ),
        'execute_callback'    => 'myplugin_ability_get_book',
        'permission_callback' => static function ( $input ) {
            return current_user_can( 'read_post', (int) ( $input['id'] ?? 0 ) );
        },
        'meta'                => array(
            'annotations' => array(
                'readonly'    => true,
                'destructive' => false,
                'idempotent'  => true,
            ),
            'public'      => true,   // discoverable by REST/MCP/agents — default false
        ),
    ) );
}

function myplugin_ability_get_book( $input ) {
    $post = get_post( (int) $input['id'] );
    if ( ! $post || 'myplugin_book' !== $post->post_type ) {
        return new WP_Error( 'myplugin_not_found', __( 'Book not found.', 'my-plugin' ) );
    }
    return array(
        'id'    => $post->ID,
        'title' => get_the_title( $post ),
        'isbn'  => (string) get_post_meta( $post->ID, '_myplugin_isbn', true ),
    );
}
```

| Arg | Required | Notes |
|-----|----------|-------|
| name | yes | `namespace/ability-name` — lowercase, dashes, one slash; prefix with your slug |
| `label`, `description` | yes | Agents read the description to decide when to call it — be precise |
| `category` | yes | Must already be registered with `wp_register_ability_category()` |
| `execute_callback` | yes | Returns data or `WP_Error` |
| `permission_callback` | yes | Returns `true`, `false`, or `WP_Error`; receives the input |
| `input_schema` / `output_schema` | no | JSON Schema — use them; input is validated against the schema |
| `meta.annotations` | no | `readonly`, `destructive`, `idempotent` hints for clients |
| `meta.public` | no | Expose to REST/MCP/agents. **Defaults to `false`** |
| `meta.show_in_rest` | no | REST exposure; defaults to `public` |

Execute from PHP:

```php
$ability = wp_get_ability( 'my-plugin/get-book' );
$result  = $ability ? $ability->execute( array( 'id' => 42 ) ) : null;
```

### Security rules for abilities

**`permission_callback` is the whole security model.** The same callback is enforced when the ability runs over REST. The `__return_true` rule from REST routes applies unchanged: only for genuinely public, read-only data.

**The permission check sees the input — use it.** Object-level checks (`edit_post`, `read_post`, `delete_post` with the ID) belong here, not in the execute callback.

**Annotations are hints, not enforcement.** `readonly => true` does not stop your execute callback from writing. Clients and agents use annotations to decide whether to ask the human for confirmation — mislabeling a destructive ability as `readonly` removes that safety net. Mark anything that deletes, publishes, sends email, spends money, or changes users/roles as `destructive => true`.

**Keep `public` off unless it's needed.** A public ability is advertised to every agent connected to the site. Register internal helpers with `public => false`.

**Assume the caller is an AI acting on a user's behalf** — possibly manipulated by prompt injection from content it read elsewhere. That is exactly why the capability check must be strict: the agent can do whatever the logged-in user can do through your ability, so the ability should allow no more than the user's own capabilities permit.

**Constrain input with the schema.** `additionalProperties => false`, `enum` for fixed choices, `minimum`/`maxLength` for bounds. Still sanitize in the execute callback; the schema is validation, not sanitization.

**Return the minimum.** Output flows back into a model's context and possibly to a third-party provider. Do not include emails, tokens, private meta, or other users' data the requester couldn't already see.

---

## AI Client (WordPress 7.0+)

### Calling a model

```php
$builder = wp_ai_client_prompt( $prompt_text )
    ->using_system_instruction( 'You write concise product descriptions. Output plain text only.' )
    ->using_temperature( 0.4 )
    ->using_max_tokens( 300 );

if ( ! $builder->is_supported_for_text_generation() ) {
    return new WP_Error( 'myplugin_ai_unavailable', __( 'No AI provider is configured.', 'my-plugin' ) );
}

$text = $builder->generate_text();

if ( is_wp_error( $text ) ) {
    return $text;
}
```

Builder methods: `with_text()`, `using_system_instruction()`, `using_temperature()`, `using_max_tokens()`, `using_model_preference()`, `as_json_response()`. Generators: `generate_text()`, `generate_image()`, and siblings — all return `WP_Error` on failure.

`is_supported_for_text_generation()` (and the image/speech/video variants) check availability **without** making an API call or incurring cost. Use them to decide whether to show AI UI at all.

### Credentials: never handle keys yourself

With the AI Client, **plugins never touch API keys** — the site owner configures a provider under Settings → Connectors and WordPress routes the request. Do not add your own "paste your OpenAI key" field when the AI Client covers the use case.

Keys resolve in order: environment variable (`{PROVIDER}_API_KEY`), then a `wp-config.php` constant, then the database option. Keys saved through the admin screen sit in `wp_options` **unencrypted** (masked in the UI only). If your plugin integrates a non-AI service and must store a key, recommend a constant or environment variable in your docs, never echo the stored key back into a field, and never log it.

### Security rules for AI features

**Every AI feature is a server-side endpoint with a capability check.** Core's guidance is to build one REST route per AI feature, with granular permissions — not to expose a generic "send any prompt" endpoint to the browser.

```php
register_rest_route( 'myplugin/v1', '/describe/(?P<id>\d+)', array(
    'methods'             => WP_REST_Server::CREATABLE,
    'callback'            => 'myplugin_rest_describe',
    'permission_callback' => static fn( $r ) => current_user_can( 'edit_post', (int) $r['id'] ),
) );
```

**Who can trigger it is also a cost question.** Each call spends the site owner's money, and there is no spend cap in core. Restrict AI features to users who need them, rate-limit per user, and never wire a prompt to an unauthenticated (`nopriv`) or front-end visitor action without explicit owner opt-in and throttling.

```php
// Per-user throttle: at most 20 generations per hour
$key   = 'myplugin_ai_count_' . get_current_user_id();
$count = (int) get_transient( $key );
if ( $count >= 20 ) {
    return new WP_Error( 'myplugin_rate_limited', __( 'Please wait before generating again.', 'my-plugin' ), array( 'status' => 429 ) );
}
set_transient( $key, $count + 1, HOUR_IN_SECONDS );
```

Site owners can block prompts globally or per role with the `wp_ai_client_prevent_prompt` filter — respect `WP_Error` returns and do not work around it.

**Model output is untrusted input.** Treat generated text exactly like text from an anonymous visitor — it can contain anything the model was steered into writing, including HTML and script.

```php
echo wp_kses_post( $text );              // HTML context
echo esc_html( $text );                  // plain-text context
update_post_meta( $id, '_myplugin_ai_summary', sanitize_textarea_field( $text ) );
```

Never pass model output to `eval()`, `call_user_func()`, `$wpdb->query()`, `do_shortcode()`, `do_blocks()`, `include`, file paths, `wp_remote_*()` URLs, `update_option()` names, or role/capability APIs. With `as_json_response()`, validate the decoded structure against what you expect before using any field.

**Prompt injection.** When a prompt includes content the requester did not write — post content, comments, product reviews, fetched web pages — that content can contain instructions aimed at the model ("ignore previous instructions and…"). You cannot filter this out reliably. Contain it instead:

- Put untrusted content in the user turn, clearly delimited; keep your instructions in the system instruction.
- Never let model output *decide* a privileged action. If the model suggests deleting, publishing, emailing, or changing permissions, a human with the right capability must confirm it.
- Don't give the model tools or abilities beyond what the current user could do themselves.

**Personal data goes to a third party.** Anything in a prompt is sent to the configured provider. Do not include emails, addresses, order data, or private content without the site owner opting in, and disclose it in your privacy policy text (`wp_add_privacy_policy_content()` — see `references/privacy.md`).

---

## Ask before you build (AI features)

These change the design and cannot be inferred from "add an AI summary button":

- **Who can trigger generation?** Every call costs the site owner money.
- **What content goes into the prompt?** Anything containing personal data or other users' content triggers privacy obligations and prompt-injection risk.
- **Does output get published automatically, or reviewed by a human first?** Automatic publishing of model output is where injection becomes defacement.
- **Should this be an ability agents can call?** If yes: `public`, annotations, and a strict `permission_callback`.

## Pitfalls

- `permission_callback => '__return_true'` on an ability that writes
- Annotating a destructive ability `readonly`
- `meta.public => true` on internal helpers
- A generic "run this prompt" REST route or `nopriv` AJAX action
- No per-user rate limit on generation
- Echoing model output without escaping
- Using model output as a function name, SQL fragment, URL, file path, or shortcode
- Auto-publishing generated content
- Asking users to paste provider API keys into your own settings when the AI Client exists
- Sending personal data to a provider without disclosure
- Calling `wp_ai_client_prompt()` without a `function_exists()` guard in a plugin that supports WordPress below 7.0
