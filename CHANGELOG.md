# Changelog

All notable changes to this skill are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/):

- **Major** — the skill's structure or workflow changes in a way that affects how it is installed or invoked.
- **Minor** — new references, new scanner checks, or new security guidance.
- **Patch** — corrections, false-positive fixes, and wording.

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

[1.1.0]: https://github.com/ararai1991/wp-plugin-skill/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ararai1991/wp-plugin-skill/releases/tag/v1.0.0
