# Daily Bloom — 日常

Zen task management: Kanban, GitHub-style history heatmap, focus timer,
n8n-style automation flows, theme store, and personal insights.

Flutter (app) + Express (API) + Postgres (DB).

## Run it locally

You need: Flutter SDK, Node 18+, Docker Desktop.

```powershell
# 1. Database (first time only — creates the volume + seeds demo data)
docker compose up -d

# 2. Backend (own terminal — keep it running, logs live here)
cd server
npm install
npm run dev        # migrate is automatic on `npm start`; for dev run once:
npm run migrate

# 3. App (another terminal, project root)
flutter pub get
flutter run                    # local API (localhost:8080)
flutter run --dart-define=BLOOM_API=https://your-api.onrender.com   # cloud API
```

Sign up in the app (`Create an account`) and continue directly into
onboarding. New email accounts receive a verification email. One server at a
time on `:8080` — a second one dies with `EADDRINUSE`.

## Tests

```powershell
cd server
npm test                       # API integration (needs DB + API + test env)
flutter test                    # app unit + widget tests
flutter analyze                 # must report "No issues found!"
```

For the backend integration tests, start Docker Desktop first, then use two
terminals with the test-only auth bypass enabled:

```powershell
# Terminal 1
docker compose up -d
cd server
$env:DATABASE_URL='postgres://bloom:bloom_ci_password@localhost:5433/daily_bloom'
$env:NODE_ENV='test'
$env:ENABLE_TEST_BYPASS='1'
$env:TEST_BYPASS_TOKEN='local-test-secret'
npm run migrate
npm run dev

# Terminal 2
cd server
$env:TEST_BYPASS_TOKEN='local-test-secret'
npm test
```

Push to GitHub and CI runs all of the above (`.github/workflows/ci.yml`).

## Project map

| Path | What lives there |
|---|---|
| `lib/main.dart` | Entry: theme preload → `AuthGate` (login vs app) |
| `lib/screens/` | One screen per tab/feature (`home`, `folders`, `goals`, `inbox`, `rules`, `store`, `settings`, `insights`, …) |
| `lib/data/api_client.dart` | `BloomApi` — every backend call + models |
| `lib/data/auth_store.dart` | Login state, token persistence, verification |
| `lib/data/focus_controller.dart` | App-wide focus timer |
| `lib/theme/sakura_theme.dart` | 3 store palettes + `ThemeStore` (live re-skin) |
| `lib/widgets/` | Cards, nav, heatmap, petals, motion helpers |
| `server/src/index.js` | API startup, middleware, and route registration |
| `server/src/routes/` | Auth, task, folder, focus, store, insight, rule, and AI routes |
| `server/scripts/migrate.js` | Ordered, idempotent DB migrations |
| `server/test/api.test.js` | Integration suite (17 tests) |
| `db/` | `schema.sql`, `seed.sql`, `migration_003`–`009` |

Auth: Firebase email/Google/Apple sign-in with Firebase ID tokens
(`Authorization: Bearer …`). New accounts get 450 tokens and a starter flow.
Docs: `PRIVACY_POLICY.md`,
`android/key.properties.example` (release signing how-to).

Release APKs require a configured Firebase project and Android signing key;
debug signing and placeholder Firebase configuration are rejected by CI.
Apple sign-in additionally requires the Apple Sign In capability, Firebase
Apple provider configuration, and the production Service ID/redirect setup
for non-Apple platforms.

## Conventions for contributors (human or AI)

- Backend responses: data as JSON, failures as `{ error: "…" }`.
- New tables go in a new `db/migration_*.sql` (re-runnable!) and get
  appended to `server/scripts/migrate.js` `ORDER`.
- Protected routes use `requireAuth`; per-user tables filter
  `WHERE user_id = $1` (never trust ids from the client).
- History is append-only (`task_events`, `rule_runs` capped at 200/rule).
- UI follows the Sakura system (`SakuraColors`, `cardDecoration()`),
  screens stay in `lib/screens/`, shared pieces in `lib/widgets/`.
- Keep `flutter analyze` clean and cover new models with unit tests.
