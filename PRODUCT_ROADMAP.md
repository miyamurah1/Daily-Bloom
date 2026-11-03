# Daily Bloom Product Roadmap

This roadmap prioritizes user trust and daily usefulness over adding more
surfaces. The product promise is: **complete tasks, see proof, grow**.

## Phase 1 — Ship safely

- [x] Require real Firebase configuration and release signing in APK CI.
- [x] Protect the test-only auth bypass.
- [x] Add sanitized liveness/readiness health checks.
- [x] Validate task payloads at the API boundary.
- [x] Make migrations concurrency-safe.
- [x] Make wallet rewards idempotent and server-authoritative for accounts.
- [x] Persist AI usage caps in PostgreSQL.
- [ ] Run the full API integration suite with Docker in CI and locally.
- [ ] Verify Firebase login, Google login, deletion, export, and offline recovery
      on real Android, iOS, web, and desktop builds.
- [x] Keep signup sessions continuous and add email-verification recovery UI.

**Exit criteria:** no release artifact uses placeholder Firebase settings,
debug signing, or a localhost API; account data remains isolated and deletable.

## Phase 2 — Improve activation and daily UX

- [x] Make the first task flow visible near the top of Today.
- [x] Make onboarding personalization genuinely optional.
- [x] Reduce the cold-start splash delay.
- [ ] Measure time-to-first-task and time-to-first-completion.
- [ ] Make quick capture the primary action on every platform.
- [x] Add clear saved/syncing/synced/offline/attention states.
- [ ] Reduce new-user exposure to AI, rules, store, and advanced settings.
- [ ] Add a single “What should I do next?” action.
- [ ] Test the first session with at least five people who did not build the app.

**Exit criteria:** a new user can plant and finish one task in under two minutes
without needing to understand tokens, habits, goals, or automations.

## Phase 3 — Scale the data architecture

- [x] Serialize local preference writes and use collision-resistant temporary IDs.
- [ ] Move task cache and outbox from `SharedPreferences` to a transactional
      cross-platform local database.
- [ ] Add schema versioning and migration tests for local data.
- [ ] Add conflict states instead of silently replacing divergent edits.
- [x] Version and recover the local task-cache envelope without losing valid rows.
- [ ] Paginate task history, inbox, rule runs, and exports.
- [ ] Add persistent background sync with exponential backoff.
- [ ] Add database backup/restore drills and retention documentation.
- [ ] Split large screens and repositories into feature modules.

**Exit criteria:** thousands of tasks remain responsive, offline edits survive
process termination, and sync failures are recoverable without data loss.

## Phase 4 — Retention, accessibility, and operations

- [ ] Complete TalkBack, VoiceOver, keyboard, 200% text, and high-contrast audits.
- [ ] Ensure status and heatmap meaning never depends on color alone.
- [ ] Add privacy-safe product metrics: activation, completion, retention, sync
      failures, notification opt-in, and guest-to-account conversion.
- [x] Add request IDs and structured privacy-safe HTTP logs.
- [x] Add explicit external-AI opt-in with local-only fallback.
- [x] Replace placeholder support/privacy contact details with in-app feedback.
- [x] Add in-app feedback with privacy-safe diagnostic context.
- [ ] Improve web SEO, sharing cards, install metadata, and loading states.

**Exit criteria:** the app is usable with assistive technology, support can
diagnose failures, and retention improvements are measured without collecting
task content.

## Additional product decisions

1. Keep the core navigation around **Today**, **Focus**, and **Progress**.
2. Treat Tasks, Habits, and Goals as the user-facing mental model; keep rules,
   AI, store, and advanced analytics progressively disclosed.
3. Keep gamification subordinate to completion: one understandable balance,
   transparent rewards, and no guilt-driven streak messaging.
4. Do not monetize basic task capture, data export, or offline access.
5. Review every new feature against one question: does it help the user finish
   today's important work with less friction?
