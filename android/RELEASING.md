# Releasing Pulse Strength for Android

Everything that can be prepared in the repository is prepared (signing, shrinking, versioning, CI, store text and graphics, privacy
policy). What is left needs **your** accounts and decisions and cannot be done from here: they are the steps below, in order.

## 0. Decisions before the first upload

| Decision | Why it matters now |
| --- | --- |
| **Application id** (`applicationId` in `app/build.gradle.kts`, currently the placeholder `health.pulse.strength`, the same string as the iOS bundle id) | The id of a Play app can **never** be changed after the first upload. Pick the final one first (for example `health.pulse.strength` or the id of the main Pulse app if this feature will live inside it) and search-and-replace the old one (`namespace` stays: it is only a code package). The CI workflow also names it (`packageName` in `.github/workflows/strength-android.yml`). |
| **Developer account type** | A *personal* account created after 13 Nov 2023 must run a **closed test with at least 12 testers for 14 continuous days** before it may publish to production ([Google's rule](https://support.google.com/googleplay/android-developer/answer/14151465)). An organization account (needs a D-U-N-S number) does not. Plan the 14 days. |
| **Privacy policy** | The dedicated page `strength-privacy.html` / `strength-datenschutz.html` in this repository is a draft written from what the app does (offline, no data collected). **Have it reviewed, merge it, and check that `https://pulse-health.github.io/strength-privacy.html` loads before submitting.** If you move to another host or domain, change `PrivacyLinks.policyUrl` in the app too. |
| **Health Connect** | The app declares `android.permission.health.WRITE_EXERCISE` (opt-in, write-only). That makes Google review the app's health data use (section 3.6). If you would rather ship v1 without it, remove it completely so that nothing promises it: delete the `uses-permission`, the two `PermissionsRationaleActivity` entries and the `<queries>` block in `app/src/main/AndroidManifest.xml`; the `health/` package, the Health Connect section of `ui/settings/SettingsScreen.kt` and the writer in `services/PulseServices.kt`; the `androidx.health.connect:connect-client` dependency (`app/build.gradle.kts`, `gradle/libs.versions.toml`; while it stays it merges an exported service into the manifest) and the `hc_rationale_*` strings; and the Health Connect text in `strength-privacy.html` / `strength-datenschutz.html` (section 5, the table row about the setting) and in both `store/metadata/android/*/full_description.txt`. |
| **Exact alarms for the rest alert** | The rest-over alert is on time without any permission on Android 8-11 and 14+, and a few seconds late at most elsewhere (see "Known limitations"). If you want it exact on Android 12-13 and when the app is in the background on 14+, add `<uses-permission android:name="android.permission.USE_EXACT_ALARM" />` (granted at install on Android 13+; Google Play allows it only for apps whose core function is an alarm, timer or calendar, and asks you to declare it) or `SCHEDULE_EXACT_ALARM` (the user must allow "Alarms & reminders" on Android 14+). The code uses an exact alarm automatically whenever the permission is held; nothing else changes. Without it, no declaration is needed. |

## 1. One-time: create the upload key

```sh
keytool -genkeypair -v -keystore pulse-upload.jks -alias pulse-upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

Keep `pulse-upload.jks` and its passwords in a password manager and **never commit them** (`android/.gitignore` already excludes
`*.jks`, `*.keystore` and `keystore.properties`). Enable **Play App Signing** when you create the app in Play Console: Google keeps the
real app-signing key, you only hold the *upload* key, and a lost upload key can be reset by Google.

For local release builds create `android/keystore.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/pulse-upload.jks
storePassword=...
keyAlias=pulse-upload
keyPassword=...
```

## 2. Build locally

```sh
cd android
./gradlew :core:test :app:testDebugUnitTest :app:lintDebug      # what CI runs on every pull request
./gradlew :app:bundleRelease -Ppulse.versionName=1.0.0 -Ppulse.versionCode=1 -Ppulse.requireSigning=true
# -> app/build/outputs/bundle/release/app-release.aab   (upload this)
# -> app/build/outputs/mapping/release/mapping.txt       (upload it too: it de-obfuscates crash reports)
```

Without a keystore the same command produces an **unsigned** bundle (the `-Ppulse.requireSigning=true` flag turns that into an error).
Requirements: JDK 17 or newer, Android SDK platform 37 and build-tools 36 (Gradle downloads them when `ANDROID_HOME` has the license
files; otherwise install them with `sdkmanager "platforms;android-37.0" "build-tools;36.0.0"`).

**Versioning.** `versionName` is what users see (`-Ppulse.versionName`, default in `app/build.gradle.kts`); `versionCode` must increase
with every upload (`-Ppulse.versionCode`, or `PULSE_VERSION_CODE`; CI uses the run number plus the optional repository variable
`ANDROID_VERSION_CODE_OFFSET`). Tag a release as `android-v1.0.0`.

## 3. One-time: Play Console

Create the app (App, free, "Health & Fitness"), then work through *Dashboard > Set up your app*:

1. **Store listing.** Text lives in `store/metadata/android/{en-US,de-DE}/` (title ≤ 30, short ≤ 80, full ≤ 4000 characters; the files
   were checked against these limits), graphics in `store/graphics/` (icon 512×512, feature graphic 1024×500) and phone screenshots in
   `store/graphics/phone-screenshots/` (rendered from the real screens by `StoreScreenshotsTest`, see section 6). Paste them in the Console,
   or upload the text with `fastlane supply --metadata_path store/metadata/android --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs` if you use fastlane (graphics and release notes are uploaded separately). Release notes: `store/whatsnew/`.
2. **Privacy policy URL**: `https://pulse-health.github.io/strength-privacy.html` (German: `.../strength-datenschutz.html`).
3. **App access**: "All functionality is available without special access" (there is no login).
4. **Ads**: No.
5. **Content rating**: answer the IARC questionnaire truthfully (no violence, no user-generated content, no sharing, no purchases,
   no location): the expected result is the lowest rating (PEGI 3 / Everyone).
6. **Target audience**: 18 and over (keeps the app out of the Families programme; it is a fitness tool for adults).
7. **Data safety**: "Does your app collect or share any of the required user data types?" **No.** All data stays on the device; the
   app has no network permission (a unit test and a CI step guard that). Health Connect writes are local to the phone and Android's
   own backup is a system feature, neither counts as "collection" by the developer. Link the privacy policy.
8. **Health apps declaration** (App content > Health apps): the app is a fitness/workout tracker; it uses Health Connect with the single
   permission `WRITE_EXERCISE` to *write* finished strength workouts (start, end, title, note), opt-in, off by default, it never reads.
   The privacy policy shown in Health Connect (`PermissionsRationaleActivity` opens `PrivacyLinks.policyUrl`) must be the same policy
   as in the listing ([Google's guidance](https://developer.android.com/health-and-fitness/guides/health-connect/publish/declare-access)).
9. **Government app / financial features / news / COVID-19**: all No. **Foreground service permissions**: none declared (the app
   uses no foreground service). **Exact alarms**: not declared (see the decision table in section 0). **Advertising ID**: No (the
   app does not use it and declares no `AD_ID` permission; the Console asks for this declaration for every app that targets
   Android 13 or newer).
10. **EU trader status** (Settings > Developer account, needed to distribute in the EU): declare whether you act as a trader; a trader
    status shows your contact details on the store listing.
11. **Pricing & distribution**: choose countries; the app is free.

Then upload the first `.aab` to **Internal testing** (the Console needs one manual upload before the API can publish), add testers, and
install from the Play link on real devices (section 5). For a new personal account run the **closed test** (12 testers, 14 days) next, then
apply for production access from the Dashboard.

## 4. Release from CI

The workflow `strength-android` verifies every pull request. On a tag `android-vX.Y.Z` (or *Run workflow* with "deploy") it builds the
**signed** bundle and uploads it to Google Play. Only the `deploy` job sees the signing key and the Play service account: they are
secrets of the GitHub **environment** `google-play`, not repository secrets (a repository secret is readable by every workflow of every
branch, so the environment's reviewers would protect nothing). One-time setup:

1. Google Cloud: create a service account, give it access in *Play Console > Users and permissions* (Release manager), and create a
   JSON key.
2. GitHub *Settings > Environments > New environment* `google-play`. Add the five **environment secrets**:
   `ANDROID_KEYSTORE_BASE64` (`base64 -w0 pulse-upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
   `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON` (the whole JSON file).
3. On that environment set **required reviewers** (you) and **deployment branches and tags** to the tag pattern `android-v*` (and
   `main`, if you want to release by hand from main). A run then waits for your approval before it can read any secret.
4. Optional repository variable `ANDROID_VERSION_CODE_OFFSET` (added to the run number to make the `versionCode`).

What runs: `verify` (tests, lint), `version` (reads `X.Y.Z` from the tag, refuses a tag that is not on `main`, or uses
`pulse.versionName` of `android/gradle.properties` / `1.0.0` for a manual run), `release-build` (an unsigned R8 build and the check
that the release APK asks for no network permission; no secrets) and `deploy` (the signed build, the signature and permission check
and the upload). A **tag push always uploads a draft to the `internal` track**: promote it in the Console. A manual run lets you choose
the track and `draft` or `completed`; until the app has been published once the Play API only accepts `draft`, which is the default.

The upload step is `r0adkll/upload-google-play@v1`; nothing in it was run from here (it needs your credentials), so expect to fix a
detail on the first run. Pin the action to a commit SHA if you want it immutable.

## 5. Test on real devices before every production rollout

The automated tests run on the JVM (Robolectric) and cannot show these, so check them by hand on at least one Android 13+ phone and one
older one (Android 8-12), in light and dark mode:

- Start a workout, background the app, lock the phone: the **ongoing notification** appears with the right buttons; **Log set**, the
  **weight −/+** buttons and the **rest −15 s / +15 s / Skip** buttons work from the lock screen; the notification disappears when the
  workout ends.
- Let a **rest finish with the screen off**: sound and vibration arrive within a few seconds; the notification then shows "Go".
  Repeat after switching to two other apps (on Android 14+ the system removes the in-process alarm then), and after force-stopping
  the app from the recent-apps list. Try an Android 12 or 13 phone too: it has only the "approaching" alarm (see Known limitations).
- Tap the **ongoing notification** with the app swiped away from the recent-apps list: the running workout must open, not the hub.
- Android 13+: the notification permission prompt appears when the first workout starts; denying it must not break anything.
- Android 16: the notification can appear as a *Live Update* chip in the status bar (user setting).
- **Health Connect**: turn it on in Settings, finish a workout, check the session in Health Connect; turn it off and check nothing more
  is written. Check the "How this app uses your data" screen opens from Health Connect.
- Rotate the phone, fold/unfold (foldable) or resize the window (tablet / desktop mode): nothing may clip or lose state.
- Font size 200 % and display size large; TalkBack on the active workout screen.
- Kill the process during a workout and reopen the app: the workout is restored.
- Backup/restore: `adb shell bmgr backupnow health.pulse.strength` then reinstall: templates and history return, the unfinished workout
  does not.
- Install the **release** (R8-shrunk) build, not only the debug build, and click through every screen: shrinking bugs only show there.

## 6. Store screenshots

Six phone screenshots (1080 × 2160: Strength hub, recovery and history, active workout in light and dark, workout summary, exercise
progress) are committed in `store/graphics/phone-screenshots/`. They are rendered from the real screens with the demo data
(`StrengthAppEnvironment`'s sample templates and history, a frozen date in January 2026, the Free Exercise DB form photos), not
captured on a device. To refresh them after a UI change:

```sh
cd android && ./gradlew :app:testDebugUnitTest --tests '*StoreScreenshotsTest*'
cp app/build/screens/store/*.png store/graphics/phone-screenshots/
```

Play wants 2-8 phone screenshots, each 320-3840 px with an aspect ratio of at most 2:1; these are exactly 1:2. Replace them with
real-device screenshots if you prefer; the Console accepts either.

## 7. After release

- Upload `mapping.txt` with the bundle (the CI job does) so *Android vitals* shows readable crash traces.
- Check the **pre-launch report** in the Console and *Android vitals* (crashes, ANRs) for the first days; use a staged rollout
  (for example 10 % then 50 % then 100 %) for production.
- Every upload needs a higher `versionCode`. Update `store/whatsnew/` and the listing when features change; update the privacy policy
  **before** shipping a change that touches data (for example an internet feature).

## Known limitations of this first Android release

- **Phone only.** The iOS app has an Apple Watch companion (heart rate, mirrored workout); the Android app has no Wear OS companion and
  therefore no heart-rate display. The core was ported without the phone-to-watch sync protocol.
- **English only** (the iOS app is English only too) and **kilograms only**.
- **Rest alert timing without special permissions** (the app declares no exact-alarm permission and runs no foreground service):
  Android 8-11 use an exact `PendingIntent` alarm; Android 14 and newer use an exact in-process alarm (the system deletes it about ten
  seconds after the app becomes "cached", that is after the user went to other apps) and an inexact backup; Android 12-13 use only the
  backup. The backup is not set for the end of the rest but early enough that the system's delay window ends exactly at the end
  (`RestAlerts` explains the arithmetic); it relies on how Android delays inexact alarms, so on a device that behaves differently the
  alert can be late, never missing. In Doze or after the system ended the process the alert can be late by minutes. If you need
  guaranteed timing, the next steps are an exact-alarm permission (section 0) or a foreground service (`specialUse`, needs a Play
  declaration).
- **History size.** Finishing a workout and starting the app rewrite the whole history file on the main thread. Measured on a desktop
  JVM: 0.2-0.4 s per Finish at 500-1000 workouts, 3-8 times that on a slow phone; it is jank, not an ANR (roughly 3000 workouts would
  be needed for that). Writing off the main thread is the next step if it matters.
- **Open-source notices.** Settings > About says the app is built with open-source software under the Apache License 2.0 but the app
  ships no licenses screen; Apache 2.0 asks for its text to accompany the binary. Decide before a wide release (a static notices asset
  or a licenses plugin). The 50 form photos come from the Free Exercise DB (Unlicense); the attribution is shown in the app.
- **Parity with iOS.** Android v1 ports the iOS strength core as it was when the Android work started; later iOS features (body
  weight and weigh-in reminders, training plans and rotations, rep ranges, template notes, the YouTube import tool) are not ported
  (see `README.md`).
- Muscle recovery is a simple documented rule of thumb (`RecoveryModel`), not medical advice.
