# Changelog

All notable changes to this skill are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/):

- **Major** — the skill's structure or workflow changes in a way that affects how it is installed or invoked.
- **Minor** — new references, new scanner checks, or new security guidance.
- **Patch** — corrections, false-positive fixes, and wording.

## [1.2.0] — 2026-10-30

Security refresh covering July–October 2026: the actively exploited plugin and core incidents of the quarter, WordPress core security releases 7.1.2–7.1.4, and the WordPress 7.2 beta.

### Added

- **`security.md` Part 3, sections I–P**, eight new incident patterns, each with vulnerable and fixed code:
  - **I. Trust carried between requests.** Bricksforge (CVE-2026-85097, CVSS 9.8–10.0, exploited from October 7) wrote an upload to a client-supplied URL. Covers GIF/PHP polyglots, extension-encoding evasion, and nonces minted by public actions.
  - **J. Staging files in web-reachable paths.** The core upgrade staging flaw fixed in 7.1.4 was exploited the next day (18,500 requests in 21 hours).
  - **K. Decoding after sanitizing.** CVE-2026-87902 (core, CVSS 9.2) was a path traversal through percent-encoded octets that `sanitize_title()` preserves. It was probed within hours of the patch.
  - **L. Request data shaping core queries, and REST batching.** Covers the wp2shell chain (CVE-2026-63030 + CVE-2026-60137, CISA KEV), `wp_parse_id_list()`, `allow_batch`, and superglobals inside REST callbacks.
  - **M. Exports that become imports.** Backuply (CVE-2026-93953) and Export and Import Users and Customers (CVE-2026-104368) both escalated a subscriber to administrator, and core's WXR export had second-order SQL injection. Covers CSV dialects, hand-built SQL dumps, roles from imports, and formula injection.
  - **N. Hook names and post values from input.** The `{status}_{type}` collision fixed in 7.1.3, where status `delete` fired `delete_post`. Also notes that `wp_insert_post()` checks no capabilities.
  - **O. Remote-management keys are root credentials.** The UpdraftCentral stolen-key incident of October 18–19, with design rules for anyone building dashboard or SaaS-connect features.
  - **P. Client-side sinks and trusted third-party HTML.** jQuery `$( string )`, Interactivity API updates, oEmbed trusted-provider bypass, and XSS through usernames and privacy requests.
- **`security.md` §8: storing credentials with the Secrets API** (WordPress 7.2+). Feature detection, fallback order, `->reveal()` discipline, and migration.
- **`security.md` section H**: authorize before fetching, inverted compound capability checks, and Notes access, all from 7.1.3 and 7.1.4.
- **`security.md` Part 3 context**: exploitation now lands in minutes to hours and exploits are built from patch diffs. AI-assisted reports rose to about 66% of Wordfence's submissions. Includes what this means for a plugin team's release process.
- **`backdoor-indicators.md`**: the UpdraftCentral backdoor. It used a token-triggered Editor account with `manage_options` and `install_plugins` added, plus a persistent-cookie login bypass. Includes indicators of compromise and the remediation order.
- **`audit-checklist.md`**: Phase 7d (multi-step flows, query shaping, exports, remote control, and client-side sinks), with grep commands.
- **`rest-api.md`**: undeclared parameters skip `args` validation, and a new batch requests section.
- **`javascript-ajax.md`**: jQuery HTML-from-string XSS and Interactivity API pitfalls.
- **`testing-tools.md`**: a "Testing against WordPress 7.2" section covering admin asset concatenation removal (410 for `load-scripts.php`), the `wp_kses()` rebuild, and the Secrets API. Also new manual tests for replayed multi-step flows, export → import round trips, and mixed batch requests, plus a note on the October 21 "php2shell" PHP releases.
- **`plugin-directory.md`**: "the diff is the disclosure" release guidance, rising AI-assisted report volume, and a supply-chain note for vendors running cloud services.
- **`ai-abilities.md`**: Secrets API pointer, and AI chat file uploads as an attack surface.
- **`SKILL.md`**: new "always ask" questions for re-imported exports, user imports, and remote control. Also a non-negotiable rule to validate the final decoded value and let the server decide, and red flags from the new incidents.
- **Scanner: 24 new checks** (102 → 126):
  - Security: nonces handed out by public actions, file writes to a path from a data field, extension blocklists, fixed staging directories, decode-after-sanitize, request data shaping core queries, ID lists from the request, `allow_batch` routes, superglobals in permission callbacks, hand-built SQL dumps, `addslashes()`, CSV calls without an explicit escape, roles from imported data, `post_status`/`post_type` from requests, hook names from requests, plugin/theme installs from code, signed remote commands, registered oEmbed providers, and revealed secrets in output.
  - JavaScript (new): jQuery called on raw attribute or decoded values, and HTML sinks with non-literal values. Minified files, `build/`, and `dist/` are skipped.
  - Functionality: Secrets API without a version guard, direct links to `load-scripts.php` / `load-styles.php`, and a forced legacy kses parser.

### Changed

- The scanner now also scans non-minified JavaScript and reports the JS file count in its header.
- The "Speed matters" guidance in `SKILL.md` and `plugin-directory.md` now reflects exploitation within 90 minutes to a day of a patch.

### Fixed

- **Scanner with ripgrep:** `vendor/` and `node_modules/` were not excluded when the target directory was an absolute path or outside the current directory, so bundled libraries were scanned. On UpdraftPlus, 1.1.0 reported 5,964 security hits with ripgrep against 3,690 with grep. The difference, about 2,270 hits, came from bundled code. The grep fallback was unaffected.

## [1.1.0] — 2026-09-23

Security refresh based on WordPress ecosystem incidents and platform changes from mid-2026.

### Added

- **`references/ai-abilities.md`** — new reference for the Abilities API (WordPress 6.9+) and the AI Client and Connectors (WordPress 7.0+): registering abilities and categories, `permission_callback`, annotations, `meta.public`, server-side AI endpoints, per-user rate limiting, credential handling, treating model output as untrusted, and prompt-injection containment.
- **`security.md` Part 3 — Patterns From Recent Incidents (2026)**, drawn from the year's most severe plugin CVEs:
  - Homemade "safe unserialize" helpers (two CVSS 9.8–10.0 RCEs)
  - `is_callable()` used as an allowlist; `extract()` on attributes
  - User content — including unapproved comments — reaching `do_blocks()` / `do_shortcode()`
  - Second-order SQL injection from stored data during restore/migration
  - Import and restore features as a path to code execution via `mu-plugins`
  - Password-reset and restore keys leaked in responses
  - SSO / magic-link authentication bypass
  - Contributor-level authorization gaps (from the WordPress 7.1.1 security release)
- **`plugin-directory.md`** — WordPress.org's automated release security review, which has **blocked high-risk releases since September 9, 2026**, and the 6-hour release cooldown in effect since June 5, 2026.
- **`plugin-directory.md`** — EU Cyber Resilience Act: reporting obligations in force since **September 11, 2026** (24-hour / 72-hour / final reports via ENISA), what small vendors need in place now, and the December 11, 2027 full-compliance deadline.
- **`backdoor-indicators.md`** — the 2026 "DebugMaster Pro" pattern: backdoors disguised as developer tools, fake core files that recreate deleted admin accounts, and hardcoded credentials.
- **`audit-checklist.md`** — Phase 7b (content parsing, stored data, imports, auth flows) and Phase 7c (abilities and AI features).
- **`SKILL.md`** — new "always ask" questions for AI features and import/restore features; 2026 red flags; version metadata.
- **Scanner — 16 new checks** (86 → 102):
  - Security: homemade safe-unserialize helpers, `unserialize()` without `allowed_classes`, user content passed to block/shortcode parsers or `the_content`, `is_callable()` gates, auth cookies set for a request-supplied user, reset-key generation, hardcoded credentials in `wp_create_user()`, archive extraction, Abilities API registrations, AI Client prompts, and AI prompts from unauthenticated actions.
  - Functionality: abilities registered outside `wp_abilities_api_init`, AI Client used without a version guard, `Requires PHP` below 7.4.
- **Scanner — `--version` and `--help` flags**; the version is printed in the report header.
- `CHANGELOG.md` and semantic-version tags.

### Changed

- The generic "Deserialization" scanner check was replaced by the more precise `unserialize()`-without-`allowed_classes` check plus a separate `maybe_unserialize()` check.
- `plugin-directory.md` pre-submission checklist now requires `Requires PHP` of 7.4 or higher, matching WordPress 7.0.

### Fixed

- **Scanner false positive:** the `defined( 'ABSPATH' ) || exit;` guard — which the skill requires in every file — was reported as a "writes outside the plugin" backdoor indicator. On Custom Post Type UI this removed 13 noise hits while still flagging real writes to `mu-plugins/`.
- README understated the scanner's size: v1.0.0 had 86 checks, not 79.

## [1.0.0] — 2026-09-15

Initial release.

### Added

- `SKILL.md` — the three-gates security model, non-negotiable rules, reference map, and the "ask before you build" discipline for decisions that cannot be inferred.
- 23 references covering all 18 chapters of the WordPress Plugin Handbook, plus database, REST API, blocks, and performance.
- `scripts/wp-plugin-audit.sh` — grep-based triage scanner with security and functionality findings reported separately.

[1.2.0]: https://github.com/ararai1991/wp-plugin-skill/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ararai1991/wp-plugin-skill/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ararai1991/wp-plugin-skill/releases/tag/v1.0.0
