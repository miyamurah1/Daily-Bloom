# Daily Bloom — Privacy Policy

> Host this file publicly (e.g. GitHub Pages, your website, or a
> `dailybloom-privacy` page) and paste the URL into Play Console →
> App content → Privacy policy.
>
> Before publishing, host this policy at a public URL and make sure the
> in-app feedback route is monitored. The app does not promise a separate
> email support channel.

_Last updated: 2026-11-03_

Daily Bloom ("the app") is a personal task manager with Kanban boards,
focus timers, habits, and optional AI planning help.

## Data we collect

- **Account data:** email address and display name, handled by
  **Firebase Authentication** (email/password, Google sign-in, or Apple
  sign-in where configured).
  We never see, store, or log your password — Firebase manages
  credentials, and sign-in tokens refresh automatically.
- **Your content:** tasks, subtasks, folders, notes, habits, focus
  sessions, automation flows, inbox messages, and token balance.
- **On-device only:** offline task cache, energy labels, game progress
  (XP, streaks), and your plan for the home-screen widget.
- **We collect no location, contacts, photos, or advertising ID.**

## AI features (optional)

Planning, breakdowns, search answers, and the weekly narrative can run
through our server proxy to **Google Gemini** and (as fallback) **Groq**.
External AI is **off by default**. You must enable External AI suggestions
in Settings before an external request is made. When enabled, only the
minimum text needed for the action is sent, and local heuristics remain
available offline. Review the applicable provider policies before enabling
the feature. Daily Bloom does not sell AI data or use it for advertising.

## Voice input, widget, crash reports

- **Voice input** uses your microphone only while you hold the mic
  button in quick-add. Transcription runs through your OS speech
  service (Apple/Google), subject to their policies. The mic is never
  accessed otherwise.
- **Due-date alarms** fire once per dated task at its due time (exact
  when your OS grants it). Completing, retiming, or deleting the task
  cancels its alarm; logging out clears them all. Tapping one opens
  the task.
- **Home-screen widget** shows your top-3 plan using OS widget
  storage (and the iOS App Group shared with the app). Removing the
  widget removes its data.
- **Crash reports** (Sentry, opt-in: anonymous exception, OS version, app
  version — never task content) are sent only in releases built with
  reporting configured, and you can switch them off any time in
  Settings → Crash reports.
- **Usage analytics** (Firebase Analytics): pseudonymous aggregate
  events that help us understand whether the app actually helps —
  e.g. account created, task planted, task finished, focus session
  started/completed (duration only), habit checked. **Never** your
  task titles, notes, email, or any content you write. Firebase may process
  event data as a service provider; there is no advertising use.

## How it is used

Your data exists solely to run the app: signing you in, syncing your
tasks across your devices, and powering streaks, history, and insights.
We do not sell, share, or use your data for advertising.

## Storage and security

- Data is stored on our secured database and transmitted over HTTPS.
- Sign-in uses short-lived Firebase tokens that refresh automatically.
- Login and AI endpoints are rate-limited to slow down abuse.

## Your rights

- **Export:** Settings → Export sends you your tasks; calendar export
  downloads an `.ics` file you own.
- **Deletion:** delete your account any time from the app
  (Home → gear icon → Settings → Delete account). This removes your
  login, tokens, inbox, and flows immediately.

## Children

The app is not directed at children under 13.

## Contact

Use **Settings → Send feedback** for privacy questions or bug reports. The
feedback share sheet includes only app version and sync diagnostics; do not
include task content unless you choose to add it yourself.

## Changes

Material changes to this policy will be announced in the app before
they take effect.
