# Play Store release checklist

This is a preparation checklist, not a guarantee of Google Play approval. Play Console's current policy forms and review decision control the final release.

## Complete before submission

- [ ] Replace the developer and privacy contact placeholders in `PRIVACY_POLICY.md` and the in-app policy.
- [ ] Publish the policy at a public, non-geofenced HTTPS URL and enter it in Play Console. The policy must accurately match the app and companion behavior.
- [ ] Complete the Play Console Data safety form truthfully. The app sends user-selected keyboard/text and control events from the phone to the user's laptop over the local network; review Google's collection definition and disclose the flow accurately. Account for every included SDK.
- [ ] Confirm that `com.shivachaitanya07.phoneremote` is available to your Play Console account before the first upload. Application IDs cannot be changed after publication.
- [ ] Keep the upload keystore and its passwords backed up securely. Never commit them, send them in chat, or lose them. Play App Signing is recommended.
- [ ] Verify the app's target SDK is API 36 or higher. Google Play currently requires API 36 for new mobile apps and updates submitted from August 31, 2026.
- [ ] Prepare the Play listing: app name, short and full descriptions, icon, screenshots, contact email, category, content rating, target audience, and any required declarations.
- [ ] Exercise the real phone-to-Windows workflow on supported devices and Windows versions. Verify correct pairing, bad fingerprint/code rejection, lockout, connection loss, event controls, and that held keys/buttons are released on disconnect.
- [ ] Arrange an independent security review and penetration test before public release. The code changes in this repository are not a penetration test or certification.
- [ ] Provide reviewers clear instructions for the required Windows companion, local-network setup, and how to test a working session.

## Build the signed Android App Bundle

In `android_app\android`, create an upload key and a local `key.properties` file using `key.properties.example` as a template. The `.jks` file and `key.properties` are ignored by Git.

From `android_app` run:

```powershell
flutter pub get
flutter build appbundle --release
```

The bundle should appear at `build\app\outputs\bundle\release\app-release.aab`. Do not upload a debug-signed build.

## Play Console flow

1. Create the app in Play Console and complete store listing, app access, content rating, target audience, privacy policy, and Data safety details.
2. Upload the signed AAB to Internal testing first. Install it through the Play testing link and verify the release build.
3. Create a Closed testing release and collect tester feedback. Personal developer accounts created after November 13, 2023 generally need at least 12 testers opted in continuously for 14 days before applying for production access; follow the requirement shown in your Console account.
4. Apply for production access if Console requires it, answer the production-readiness questions, resolve all policy and pre-launch report issues, then submit a production release for review.
5. Use a staged rollout and monitor crashes, reviews, and policy notices after approval.

## Current project notes

- Android `targetSdk` and `compileSdk` are set to 36.
- Release Gradle signing now requires `android\key.properties`; it no longer falls back to the debug key.
- The Windows companion now requires Python 3.11+, TLS, a pinned server-certificate fingerprint, and the pairing code printed at startup.
- This project has not completed a penetration test, Google Play review, release build, or production-readiness assessment.
