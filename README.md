# Dony's Lifts for iPhone, iPad, Apple Watch, and Mac

The app's name and Icon Composer barbell-and-checklist icon now emphasize gym-set recording. The in-app accent is the original bright green; the icon has a light default background and a separate dark appearance. The bundle identifier and local/Firebase data formats are unchanged, so installing this build over the existing app keeps its saved workouts.

Native SwiftUI version of the private Setlog workout tracker. It supports the same seven-day schedule, Friday plan choice, target and last values, set-level editing and completion, notes, the 80% finish rule, and location-based day/night appearance.

The iPhone and iPad use the same universal `Setlog` target and existing bundle ID. The iPad layout is centered for a wider screen. The `DonyLiftsWatch` watchOS companion is embedded in that app. The separate `DonyLiftsMac` target is native SwiftUI for macOS. Workout data uses the same Firebase account on iPhone/iPad and Mac; the watch sends changes through the paired iPhone. Apple Fitness rings remain on-device and are not uploaded.

On Apple Watch, open the companion after opening Dony's Lifts on the paired iPhone. Browse a weekday, tap an exercise, tap a set to mark it done, or unlock to edit load/reps and add/delete sets. The current Friday plan is shown, but choose between the two Friday plans on phone or Mac. If the watch is temporarily offline, changes queue for delivery to its paired phone. The watch is not a standalone Firebase client.

On Mac, select a weekday in the sidebar and use the same Setlog email/password as the website and phone. The Mac downloads the established shared record, refreshes while open, and pauses upload if it detects a conflicting edit. Its local file and keychain are separate from the iPhone's. There is no automatic local-data migration between platforms; the shared Firebase record is the bridge.

To remove a set, tap **Unlock entries**, then the red minus button beside that set. Confirm the deletion; the remaining sets renumber and save automatically.

## Apple Fitness rings

On the iPhone, tap **Connect rings** in the top-right card and allow Setlog to read your Activity summary in Health. Setlog displays real Apple Fitness rings for the selected date. Tap a weekday to show that day's rings, or use the date picker beneath the rings to choose an earlier week. The separate **Finished** switch and workout progress still refer only to your Setlog sets; the workout schedule is a recurring seven-day template, not dated workout history. Fitness data stays on the iPhone: it is not added to Firebase, the website, or JSON backups. If Health has no Activity summary for the selected date, Setlog shows a status message instead of invented ring progress. The three Move, Exercise, and Stand rings depend on the Activity data available on your iPhone and paired Apple Watch.

## Shared record setup

1. In Firebase Console, enable Email/Password authentication and create Firestore in Production mode. Publish the owner-scoped rules in the accompanying `firestore.rules` file.
2. Open the [private Setlog site](https://dony-setlog.setyautama1999.chatgpt.site), confirm the five Thursday Hanging Leg Raise sets, and create or sign in to your Setlog email/password account. The website establishes the first shared copy. Wait for **Shared with your iPhone** and **Saved privately**.
3. Install this updated iPhone build, scroll to **Shared data**, and sign in with the same email/password. The shared website record is downloaded; your earlier local iPhone record is backed up first.

The website, iPhone/iPad, and Mac save locally while a cloud write is pending and check for shared changes while open. A concurrent edit pauses native shared saving and asks which copy to keep rather than silently overwriting one. The website's previous private database and the supplied JSON backups are not deleted. The iPhone/iPad still has **Import JSON** and **Back up** for manual recovery. Do not sign in on a new device before the website has established the shared copy.

## Build and install

Open `Setlog.xcodeproj` in Xcode 27 or later. The deployment targets are iOS/iPadOS 17, watchOS 10, and macOS 14. Choose your team in **Signing & Capabilities** for **Setlog**, **DonyLiftsWatch**, and **DonyLiftsMac**, and leave **Automatically manage signing** enabled. The iPhone/iPad target has a HealthKit read entitlement but no iCloud entitlement. Select an iPhone or iPad and run **Setlog**. To install on a paired Apple Watch, enable automatic app installation in the Watch app or select a paired Watch run destination. To run on Mac, select the **DonyLiftsMac** scheme and **My Mac**. Physical-device installation still depends on your Apple signing/provisioning setup.

The iPhone/iPad bundle ID remains `com.setyautama.setlog` so updates keep local data. Do not change it merely to silence a signing error: that would install a separate app without the existing local record. The watch and Mac bundle IDs are `com.setyautama.setlog.watchkitapp` and `com.setyautama.setlog.mac`. For TestFlight you need an Apple Developer Program team, not a free Personal Team. With a paid team, use **Product → Archive → Distribute App → TestFlight Internal Only**. The universal iOS app and embedded watch app compile for simulators, and the native Mac app compiles unsigned; the new screens have not yet been exercised on your physical devices or uploaded to App Store Connect.

The starter schedule is bundled with timestamp zero. Existing imported or saved sets are never regenerated from the template. Shared workout data uses Firebase, not iCloud, and the supplied Firebase iOS configuration is bundled as `GoogleService-Info.plist`. The unused `Setlog.entitlements` file is not attached to the target; `Setlog-HealthKit.entitlements` is attached instead. Do not enable iCloud capability for this version.
