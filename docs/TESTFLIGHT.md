# TestFlight checklist (owner)

Things the code can't do for you. Do them in this order before the first upload. Each item names the file or console it touches.

## 1. Signing and iCloud

- [ ] In the Apple Developer portal, App ID `uz.xq.chessc` has **iCloud (CloudKit)** with container `iCloud.uz.xq.chessc`, and **Push Notifications** (CloudKit sync uses silent pushes; `App/ChessCoach.entitlements` has `aps-environment`).
- [ ] Xcode → Signing & Capabilities resolves without warnings for the Release configuration.
- [ ] `CLOUDKIT_SYNC` is `1` by default (`Config/App.xcconfig`). If your signing team lacks the iCloud capability, set `CLOUDKIT_SYNC = 0` in `Config/Secrets.xcconfig`. The app then keeps a local store (`local.store`) and never syncs.

## 2. CloudKit schema → Production

TestFlight and App Store builds use the **Production** CloudKit environment. Without a deployed schema every export fails and sync silently doesn't happen.

- [ ] Run a Debug build on a device signed in to iCloud. Play one game, solve one puzzle, finish one lesson, and run onboarding with an import. That creates every record type in the Development schema: `CD_GameRecord` (including the new `revision` and `rowID` fields), `CD_PuzzleProgress`, `CD_LessonProgress`, `CD_StreakState`, `CD_UserProfile`, `CD_TrainingPlanRecord`.
- [ ] CloudKit Console → container `iCloud.uz.xq.chessc` → Schema → **Deploy Schema Changes…** to Production.
- [ ] After any model change, repeat this before the next TestFlight build. Fields are added only; never rename or delete one.

## 3. Sync check on devices (final review I4, I7)

- [ ] Device A: onboard with an import. Device B (same Apple Account, fresh install): the app should open on the tabs, not onboarding, once the profile has synced. Profile shows each game once.
- [ ] On one device: signed in, then signed out of iCloud, then signed in again. Progress is still there each time, and no "Couldn't save…" notice appears.
- [ ] Re-import from Settings on one device. The other device shows each game once, and full analyses are kept.

## 4. Legal and source links (GPLv3)

`App/Features/Settings/Preferences.swift`, `AppInfo`:

- [ ] `sourceURL`: the public repository with the exact source of the build you upload. GPLv3 requires this once binaries go to external testers.
- [ ] `termsURL` and `privacyURL`: real pages. The paywall links to both, and App Store Connect needs the privacy policy URL.

## 5. Purchases

- [ ] App Store Connect → the app → Subscriptions: **one subscription group** ("Coach Pro") holding both products, so a user has one Pro at a time and can switch plans:
  - `uz.xq.chessc.pro.yearly`, $29.99 a year, with an **introductory offer: Free trial, 3 days**, new subscribers, every territory. This is the only intro offer.
  - `uz.xq.chessc.pro.monthly`, $4.99 a month, **no introductory offer** (billed at purchase).
  - Same as `Config/ChessCoach.storekit`. The app never hardcodes a price or a trial: the paywall reads each product's price, its introductory offer and whether this Apple Account is still eligible from the store ("Try 3 days free.", "Then $29.99 a year.", "Try for $0.00"). A plan without a trial (monthly, or yearly for an account that already used its trial) shows its price and "Subscribe".
  - Add the subscription screenshot (the paywall, `docs/design/screens/final-paywall-onboarding.png`) and review notes. Paid Apps agreement and banking must be active, or sandbox purchases fail.
- [ ] **Hard paywall** (`HARD_PAYWALL = 1` in `Config/App.xcconfig`, the default): onboarding ends on the paywall and the app needs Coach Pro. Review notes for App Review: "The app analyses the user's own games and builds a training plan during onboarding before asking for a subscription. The yearly plan starts with a 3-day free trial, the monthly plan is billed at purchase; Restore, Terms and Privacy are on the paywall." Set `HARD_PAYWALL = 0` (e.g. in `Config/Secrets.xcconfig`) for a build with the free tier and Pro gates instead.
- [ ] App Review 3.1.2 asks for the subscription's name on the paywall; the minimal paywall shows the price, period and trial but not the words "Coach Pro" (the App Store's purchase sheet does). If review flags it, add "Coach Pro" to the headline (it stays under the 25-word budget only if a word goes elsewhere).
- [ ] The paywall promises a reminder before the trial ends: it schedules a local notification right after a trial starts and asks for notification permission at that moment. Check it in TestFlight (Settings → Notifications → Chess Coach) and that it fires on day 2 of the yearly trial (the day before billing).
- [ ] Choose the back end for this build:
  - **RevenueCat**: put the public Apple SDK key in `Config/Secrets.xcconfig` (gitignored) as `REVENUECAT_API_KEY = appl_…`. Set up the products, the `pro` entitlement and an offering in the RevenueCat dashboard.
  - **StoreKit only**: leave the key out. Anything that isn't an `appl_…` key (empty, a placeholder, a secret key) falls back to StoreKit 2, and the archive still works.
- [ ] Test a sandbox purchase, a restore and a trial in TestFlight. In the Simulator, plans only load when the app is run from Xcode (the scheme's StoreKit configuration); a run started with `simctl` shows "I couldn't reach the App Store" (DEBUG builds: `-demoPlans YES` shows sample plans, `-forcePro YES` skips the paywall). `StoreKitPlansTests` buy the trial through `SKTestSession` when run from Xcode (⌘U); from `xcodebuild` the StoreKit test daemon refuses the session and they record a known issue.

## 6. Privacy nutrition label (App Store Connect → App Privacy)

These answers must match `App/PrivacyInfo.xcprivacy`, and RevenueCat's manifest when RevenueCat is used.

- [ ] Tracking: **No**.
- [ ] Data collected by the app itself: **none**. Games, progress and the profile stay on the device and in the user's own iCloud private database, which Apple doesn't count as developer collection. Usernames go to chess.com and Lichess only to fetch public games.
- [ ] If RevenueCat is used: **Purchase History**, not linked to the user, not used for tracking, purpose App Functionality. This is declared in RevenueCat's `PrivacyInfo.xcprivacy`.
- [ ] Microphone and speech: on-device only, nothing collected. The usage strings are already in `project.yml`.
- [ ] Archive once, then in Xcode Organizer → the archive → **Generate Privacy Report**. Check that it lists UserDefaults (CA92.1), File Timestamp (C617.1) and RevenueCat's entries, and nothing else.

## 7. Export compliance

- [ ] Already handled: `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), so builds aren't held for the question. Confirm it in App Store Connect on the first upload.

## 8. Device measurements (not possible in the Simulator)

- [ ] Engine: run the DEBUG engine benchmark (Profile → "Engine benchmark (debug)") on the oldest supported iPhone. Record nodes per second, full-review time for a 40-move game and thermal state. Plan 4 decides on dotprod and LTO from these numbers.
- [ ] Onboarding import timing on device, on cellular and on Wi-Fi: time to the reveal (target about 10 s), and when the background quick pass and full pass finish.
- [ ] Voice: hold the mic during a phone call and with a Bluetooth headset. Expect the inline "The microphone isn't available right now.", never a crash.
- [ ] Hold-to-talk, haptics and sounds on device.

## 9. Upload

- [ ] Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` when needed) in `project.yml`, then run `xcodegen generate`.
- [ ] Archive (Release) → Validate → Distribute to App Store Connect → TestFlight. Add the internal testers first. External testers need Beta App Review, and the source link from item 4.
