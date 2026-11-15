# Signing identity

The release APK must be signed by **the upload key in `android/upload-keystore.jks`**
(untracked). Everything Google-side is matched against this certificate, so a
build signed with anything else fails Google Sign-In with
`ApiException: 10` / `DEVELOPER_ERROR` and cannot update an existing install.

| | |
|---|---|
| Keystore | `android/upload-keystore.jks` (local only, never committed) |
| Alias | `dailybloom` |
| Subject | `CN=Daily Bloom, O=DailyBloom` |
| Valid | 2026-10-16 → 2054-03-03 |
| SHA-1 | `22:D6:41:62:7F:12:1F:81:C7:DA:0B:9E:E9:7E:AF:B8:D5:77:C3:05` |
| SHA-256 | `05:55:C8:34:73:35:8A:E7:6C:4D:00:9C:7E:2F:39:EA:EA:E2:A4:06:95:4A:76:36:90:7B:A3:92:F4:83:A8:0C` |

`keyPassword` equals `storePassword`; both live in the
`ANDROID_KEYSTORE_PASSWORD` GitHub secret, alongside `ANDROID_KEYSTORE_B64`
(the keystore, base64) and `ANDROID_KEY_ALIAS` (`dailybloom`).

## Rules

- **Never let CI mint a key.** A runner-generated key is lost when the runner
  is discarded; the `BE:C1:58:10:…` key was created that way on 2026-11-03 and
  its private key no longer exists. `.github/workflows/apk.yml` fails the build
  unless the APK signer is the SHA-1 above.
- **Register every new fingerprint** on the Firebase Android app
  `com.dailybloom.app` (`1:789612027996:android:120c7517d18fb54ec28699`,
  project `daily-bloom-6aca1`). The app ships no `google-services.json` and no
  google-services Gradle plugin, so this registration is the only thing that
  creates the Android OAuth client.
- **Back the keystore up.** Without it, future APKs cannot update installed
  ones and a new certificate has to be re-registered everywhere.

## Superseded certificates

| SHA-1 (prefix) | Where it came from | Status |
|---|---|---|
| `CF:6D:49:D7:…` | APK from 2026-10-22 | registered in Firebase; no private key on hand |
| `BE:C1:58:10:…` | CI-generated key, 2026-11-03 | private key lost; remove once unused |

## Checking an APK

CI prints and enforces the signer SHA-1 (`Verify APK signer certificate`).
On a device, the login screen shows the package id and the SHA-1 the APK was
actually signed with — temporary diagnostics, removed once sign-in is green.
