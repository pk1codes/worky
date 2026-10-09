# App Check and Google Ads

Release builds need `--dart-define=USE_EMULATOR=false` (see `app/tool/release_apk.sh`). Emulator builds skip App Check.

Phone numbers and precise GPS stay on Firestore `users/{uid}`. They are not sent to Analytics or Ads.

## Status

| Area | In repo | Console |
| --- | --- | --- |
| App Check client (Play Integrity / debug) | Done | Register Play signing SHA-256 + debug tokens |
| App Check API verify on Cloud Functions | Done (`authed()`) | Optional Firebase “Enforce” toggle for other surfaces |
| Analytics `app_open` + `sign_up` | Done | Enable Analytics integration; re-download `google-services.json` if needed |
| Ads link + conversions | n/a | Link Ads `926-752-2086`; import `first_open` + `sign_up` |
| Play Data safety | AD_ID + location perms in manifest | Fill Play Console form (answers below) |

## Accounts

- Firebase: `worky-93fbc`
- Android app: `com.pk1codes.worky`
- Google Ads: Hope, customer `926-752-2086`, login `punam.kapoor@gmail.com`
- Google Play: KapoorSons Digital Solutions, personal account `8703642861541987648`

## Firebase Analytics

- [ ] Firebase → Project settings → Integrations → turn Google Analytics on for the Android app.
- [ ] If Analytics was added after the current `app/android/app/google-services.json`, replace that file with the fresh download.

## App Check

- [ ] Play Console (KapoorSons Digital Solutions) → Worky → App integrity → copy the App signing SHA-256.
- [ ] Firebase → App Check → Android app → Play Integrity → paste that SHA-256.
- [ ] For a debug build, register the debug token printed in logcat / Flutter console (`App Check token (register debug token in Firebase): …`).

The HTTP API already rejects calls that lack a valid App Check token outside the emulator.

## Link Ads

- [ ] Firebase → Integrations → Link Google Ads → customer `926-752-2086`.
- [ ] Ads → Goals → Conversions → import Firebase `first_open` and `sign_up`.
- [ ] Confirm the Play listing for `com.pk1codes.worky` is live on this Play account.
- [ ] Ads → App campaign → goal App installs → conversion `first_open`.

## Play Console Data safety (copy answers)

Declare data collection for:

| Data type | Collected | Shared | Purpose | Optional |
| --- | --- | --- | --- | --- |
| Advertising ID | Yes (Play attribution) | With Google Ads / Analytics | Advertising / analytics | No |
| Precise location | Yes (device GPS) | No (stays in Firestore `users`) | App functionality (nearby browse / post) | Yes (user can deny; posting needs a place) |
| Phone number | Yes (WhatsApp) | No (Firestore `users` only) | App functionality (contact) | No (required to finish setup) |
| Photos / video / audio | Yes (user posts) | Shown to nearby users in-app | App functionality | Yes |
| Email (Google sign-in) | Yes | No | Account management | No |

Also declare: data is encrypted in transit; users can request deletion via in-app Delete account.

## Where the data shows up

- Analytics → Attribution: campaign `first_open` counts.
- Analytics → Geography: city from IP.
- Firestore `users`: WhatsApp, plus `lat` and `lng` after the person allows location.
