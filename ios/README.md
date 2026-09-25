# Local Ledger for iOS

A native Swift 6 / SwiftUI port for **iOS 26 and later**, with iPhone and iPad layouts. The Android application stays in `app/`; this directory is an independent Apple application with no third-party dependencies or network service.

This is a development preview. The ledger tests and native SDK type checks have passed on this development Mac. On September 25, 2026, the unsigned arm64 Release build and IPA packaging also passed with Xcode 27 and the iOS 27 SDK, retaining an iOS 26 minimum deployment target. AltStore signing/installation and on-device visual/performance QA still need verification. A simulator CI workflow is included; it has not been run remotely as part of this change.

## Open and run

1. Install Xcode 26 or later, open it once, and install an iOS 26 simulator runtime.
2. Open `ios/LocalLedger.xcodeproj` and select the **LocalLedger** scheme.
3. Choose an iPhone or iPad simulator and run. No server, package download, CocoaPods, or XcodeGen is needed.
4. For your iPhone, select your development team for **LocalLedger** and **LocalLedgerWidget**, and change both bundle identifiers to unique identifiers with the widget identifier prefixed by the app identifier. Enable Developer Mode on the device.
5. Tap **Take a look around** to explore synthetic data, or add a bank and its balance to start your own ledger.

```sh
swift test --package-path ios
xcodebuild -project ios/LocalLedger.xcodeproj -scheme LocalLedger \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

After adding or removing Swift source files, regenerate the checked-in project:

```sh
python3 ios/scripts/generate_project.py
```

The generator is deterministic and uses only Python's standard library. Change signing identifiers in Xcode for local use; update the generator if those changes should persist after regeneration.

## Install with AltStore Classic

Follow the [AltStore installation guide](ALTSTORE.md). Build an optimized, unsigned device IPA for AltStore to sign:

```sh
bash ios/scripts/build-ipa.sh
```

After a successful build, the app and widget are packaged into `outputs/ios/LocalLedger.ipa`. Full Xcode setup with iOS support is required. The script does not change the Mac's global Xcode selection or require signing credentials.

## Carried over from Android

- One account per bank; opening-balance dates, corrections, and balance drill-downs.
- The original 46-bank / 563-header registry, preserving official and observed header provenance.
- All six ICICI/DCB/SBI parser profiles, conservative generic parsing, sender normalization, rejection rules, balance masking, reference extraction, and date parsing.
- Source fingerprints and bank/direction/reference deduplication. Raw message bodies are never persisted.
- Manual expenses/income, optional balance adjustment, dates, notes, transaction editing and deletion.
- Merchant nicknames and default categories; custom categories and tags; payment, merchant, and category tag inheritance.
- Period/account/direction/category/merchant/tag filters, search, and date/amount/merchant sorting. Filters are shared between Overview, Activity, and exports.
- All eight reorderable/hideable dashboard modules: balances, cash flow, daily spending, category composition, money flow, budget watch, insights, and recent activity.
- Day/week/month/year budgets scoped to a category, merchant, or tag, with pace projection, alert thresholds, pause/resume, and cycle deduplication.
- Visible, Hidden, and Demo display modes. Hidden and Demo use an independent synthetic ledger, including labels and chart proportions, and cannot mutate or export real finances.
- Detailed CSV and paginated PDF reports using Files; privacy-safe diagnostics capped at 120 events and seven days.

Balances reflect the whole ledger; only the selected account filter applies to the balance module. Budget watch always uses each budget's current calendar cycle across all accounts. Its scope is explicitly labeled so period filters do not misrepresent budget progress.

## iOS adaptations and additions

SwiftUI's iOS 26 tab bar, toolbars, buttons, pickers, menus, and sheets supply real **Liquid Glass**. Content cards use solid system surfaces to keep charts readable. System navigation, lazy lists, background parsing/storage/aggregation/report rendering, and cached balances keep work off the UI thread. Swift Charts supplies native accessible charts; the money-flow graphic uses SwiftUI Canvas.

The app includes Face ID/passcode locking, app-switcher masking, haptic feedback, Dynamic Type, VoiceOver labels, dark mode, keyboard commands, document pickers, Siri/App Intents, optional local notifications, and Home/Lock Screen quick-entry widgets. Widgets intentionally store and display no financial data, so no App Group capability is needed. An Action button or Control Center Shortcuts control can run the app's shortcut.

### SMS access is different on iOS

There is **no automatic Messages inbox scanner or Android SMS receiver** in this port. An ordinary Indian finance app cannot reproduce Android's permission-based ingestion. Apple's IdentityLookup message-filter extension also cannot write data to the containing app's shared container, so it is not used as a ledger-ingestion workaround. See [Apple's SMS/MMS filtering documentation](https://developer.apple.com/documentation/identitylookup/sms-and-mms-message-filtering).

Supported ingestion paths:

1. Copy an alert and paste it in **Import bank alert**, supplying the original sender and received date.
2. In Shortcuts, create a **Message** personal automation and pass the message text, configured bank header, and original received date into **Local Ledger → Import bank alert**. The action opens the app and respects the app lock. Behavior/confirmation depends on iOS and the automation configuration; unattended background delivery is not promised.
3. Import a Local Ledger CSV report or enter transactions manually.

Repeated reference-free alerts require the same original receipt date to deduplicate. Sender/header matching is an allowlist check, not authentication. The registry source date is June 2020; unsupported/new headers are rejected.

### Move data from Android

Export a detailed CSV from Android, transfer the file through a method you choose, and add matching banks on iOS with their **current balances**. Import via **Settings → Import CSV report**, leaving **Adjust account balances** off for historical entries already represented by those balances. Imported entries still contribute to reports and budgets. Rows are validated as one atomic operation; reimported rows/references are skipped.

CSV carries transactions, effective categories/tags, notes, merchant labels, and references. It does not carry Android budget definitions, dashboard settings, or the distinction between inherited and payment-only tags. Recreate budgets and inheritance rules on iOS. iOS exports append a transaction UUID for reliable repeat imports. CSV cells are escaped against spreadsheet formula injection. PDF is a readable summary; long field values are truncated to fit, so use CSV for exact full text.

## Storage and privacy

`LedgerCore` is a Foundation/CryptoKit Swift package with integer-paise arithmetic. `LedgerVault` is an actor that owns an atomic, versioned JSON snapshot under Application Support. A mutation is published only after a successful write; failed writes preserve the prior state, and corrupt/newer files are never silently reset. Monotonic revisions prevent delayed results from replacing newer UI state. Limits are 100,000 transactions and 20 MB per CSV import.

Files use complete iOS Data Protection and are excluded from system backups. All message processing stays in memory. There is no network client, analytics SDK, cloud sync, or background polling. Exported files contain financial information and are saved only at the user's request. Uninstalling the app deletes local records. JSON snapshots favor a small, auditable implementation; large-ledger performance still needs device profiling before any performance guarantee.

Budget notifications have generic content, no sound, and one claim per budget cycle. They are evaluated on ledger mutations and when notifications are enabled, not by a background scheduler. Face ID is optional and falls back to the device passcode.

## Verification

`Tests/LedgerCoreTests` covers parser acceptance/rejection fixtures, short-year dates, registry counts, exact money handling, duplicate imports, opening-balance boundaries, inherited tags, combined filters, budget periods/projections, CSV round trips and atomic failure, diagnostics retention, and persistence failure recovery. `LocalLedgerUITests` provides a simulator smoke test for demo navigation.

On a Mac with only Command Line Tools, the bundled Testing framework may need explicit framework and runtime paths. The helper supplies those without downloading dependencies:

```sh
bash ios/scripts/test-core.sh
```

Before distribution, run CI and verify on actual iOS hardware: onboarding/manual entry, iPad layouts, large accessibility text, Reduce Motion/Transparency, light/dark/tinted appearance, Face ID interruption and background return, notification denial/threshold deduplication, CSV/PDF Files exports, message automation with device lock, widget links, and Instruments profiling with a large synthetic ledger. No simulator screenshot or measured frame-rate claim is included until those checks run.

Apple references: [adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [native SwiftUI design](https://developer.apple.com/videos/play/wwdc2025/323/), and [App Intents](https://developer.apple.com/documentation/appintents/app-intents).
