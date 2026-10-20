# Changelog

All notable changes to Daily Bloom are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-10-20

A focused pass on the three things that decide a daily-driver's rating:
capture speed, finishing a task, and keeping work you already did.

### Added

- **Guest → account migration.** Tasks you plant as a guest now come with
  you when you sign in — nothing is wiped at the sign-in boundary anymore.
  The guest cap dialog promises migration, and it delivers.
- **Focus → done, in one tap.** Finish a focus session that was linked to a
  task and the mini-player offers **Mark done** right in the confirmation, so
  the effort converts to a completed task without hunting for it on the board.
- **Faster capture.** The quick-add sheet leads with the title field; due
  dates and repeats fold away behind a summary row. A plain task plants in
  under three seconds; the options are one tap when you want them.

### Changed

- **Sound settings tell the truth.** The "Alarm chime" switch silently
  flipped the tap-sound preference while claiming to control the daily
  reminder (whose chime is set at the OS notification level, not in-app).
  The misleading switch is gone; tap-sound and background-music toggles are
  unaffected and still work.
- Kind, non-judgmental copy throughout — no guilt, no shame, no streak-panic.

### Fixed

- Release APK builds can no longer silently ship a blank/localhost backend
  URL; the build now fails fast if the API URL is missing.

## [1.0.0] - 2026-10-19

Initial release.

[1.0.1]: https://github.com/miyamurah1/Daily-Bloom/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/miyamurah1/Daily-Bloom/releases/tag/v1.0.0
