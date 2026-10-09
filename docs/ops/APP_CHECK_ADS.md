# App Check and Google Ads

Release builds need `--dart-define=USE_EMULATOR=false`. Emulator builds skip App Check.

Phone numbers and precise GPS stay on Firestore `users/{uid}`. They are not sent to Analytics or Ads.

## Accounts

- Firebase: `worky-93fbc`
- Android app: `com.pk1codes.worky`
- Google Ads: Hope, customer `926-752-2086`, login `punam.kapoor@gmail.com`
- Google Play: KapoorSons Digital Solutions, personal account `8703642861541987648`

## Firebase Analytics

- Firebase → Project settings → Integrations → turn Google Analytics on for the Android app.
- If Analytics was added after the current `app/android/app/google-services.json`, replace that file with the fresh download.

## App Check

- Play Console (KapoorSons Digital Solutions) → Worky → App integrity → copy the App signing SHA-256.
- Firebase → App Check → Android app → Play Integrity → paste that SHA-256.
- Enforce App Check on Cloud Functions.
- For a debug build, register the debug token printed in logcat.

The API already rejects calls that lack a valid App Check token outside the emulator.

## Link Ads

- Firebase → Integrations → Link Google Ads → customer `926-752-2086`.
- Ads → Goals → Conversions → import Firebase `first_open` and `sign_up`.
- Confirm the Play listing for `com.pk1codes.worky` is live on this Play account.
- Ads → App campaign → goal App installs → conversion `first_open`.
- Play Console Data safety: declare advertising ID, precise location, and phone number.

## Where the data shows up

- Analytics → Attribution: campaign `first_open` counts.
- Analytics → Geography: city from IP.
- Firestore `users`: WhatsApp, plus `lat` and `lng` after the person allows location.
