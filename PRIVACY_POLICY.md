# Daily Bloom — Privacy Policy

> Host this file publicly (e.g. GitHub Pages, your website, or a
> `dailybloom-privacy` page) and paste the URL into Play Console →
> App content → Privacy policy.
>
> BEFORE PUBLISHING: replace `privacy@dailybloom.app` below with the
> inbox you actually monitor. Everything else is already accurate for
> the current build (Firebase Auth, AI features, widget, crash reports).

_Last updated: 2026-10-09_

Daily Bloom ("the app") is a personal task manager with Kanban boards,
focus timers, habits, and optional AI planning help.

## Data we collect

- **Account data:** email address and display name, handled by
  **Firebase Authentication** (email/password or Google sign-in).
  We never see, store, or log your password — Firebase manages
  credentials, and sign-in tokens refresh automatically.
- **Your content:** tasks, subtasks, folders, notes, habits, focus
  sessions, automation flows, inbox messages, and token balance.
- **On-device only:** offline task cache, energy labels, game progress
  (XP, streaks), and your plan for the home-screen widget.
- **We collect no location, contacts, photos, or advertising ID.**

## AI features (optional)

Planning, breakdowns, search answers, and the weekly narrative run
through our server proxy to **Google Gemini** and (as fallback) **Groq**.
Only the minimum text needed (e.g. task titles) is sent, and only when
you tap an AI action. Their free tiers may use that data to improve
their models. Don't want that? Simply don't tap the AI actions —
offline heuristics on your device cover the same features.
No AI data is sold or used for advertising, by us or anyone else.

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
- **Crash reports** (Sentry, anonymous: exception, OS version, app
  version — never task content) are sent only in releases built with
  reporting configured, and you can switch them off any time in
  Settings → Crash reports.
- **Usage analytics** (Firebase Analytics): anonymous, aggregate
  events that help us understand whether the app actually helps —
  e.g. account created, task planted, task finished, focus session
  started/completed (duration only), habit checked. **Never** your
  task titles, notes, email, or any content you write. No advertising
  or third-party sharing.

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

Questions about privacy: **privacy@dailybloom.app**

## Changes

Material changes to this policy will be announced in the app before
they take effect.
