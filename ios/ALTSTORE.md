# Install Local Ledger with AltStore Classic

Use AltStore Classic on the iPhone and AltServer on the Mac. Local Ledger requires iOS 26 or later. The Mac needs Xcode 26 or later to compile new app versions; no paid developer membership is required for this personal installation workflow.

## Build the IPA

Open Xcode and complete its first-launch setup, including the license and iOS platform support. From the repository root, run:

```sh
bash ios/scripts/build-ipa.sh
```

The script selects `/Applications/Xcode.app` for this command when the Mac still selects Command Line Tools. It builds the app and widget in optimized Release mode for a physical iPhone/iPad and packages them into `outputs/ios/LocalLedger.ipa`. AltStore signs this unsigned IPA with your Apple Account during installation. There is no need to configure a signing team in Xcode for this build.

Only continue after the script succeeds. A compiler or SDK error must be resolved before installation; the output is not a simulator build. The unsigned arm64 Release build and IPA archive validation passed with Xcode 27 on September 25, 2026. AltStore signing/installation and actual device behavior still need verification.

## Install AltStore

1. Download [AltServer for macOS](https://cdn.altstore.io/file/altstore/altserver.zip), extract it, move AltServer to Applications, and launch it.
2. Connect the unlocked iPhone by USB and trust the Mac when prompted.
3. In Finder, select the iPhone, enable **Show this iPhone when on Wi-Fi**, and click **Apply**.
4. In AltServer's menu bar menu, choose **Install AltStore**, select the iPhone, and sign in with your Apple Account directly in AltServer.
5. On the iPhone, open **Settings → General → VPN & Device Management**, select your developer account, and complete the trust/restart prompts.
6. Enable **Settings → Privacy & Security → Developer Mode** and complete the restart/confirmation.
7. Open AltStore and sign in with the same Apple Account if requested.

See the [official macOS installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) for current instructions. LocalDevVPN and SideStore are not part of this setup.

## Install Local Ledger

1. Transfer `outputs/ios/LocalLedger.ipa` to the iPhone's Files app using AirDrop or iCloud Drive.
2. Keep AltServer running with the Mac awake. Connect the phone by USB or use the same Wi-Fi network.
3. In **AltStore → My Apps**, tap **+** and select `LocalLedger.ipa`.
4. If asked about extensions, keep the app extensions so the Local Ledger widget is included. Extensions can consume additional App IDs under the free account limit.
5. Wait for installation, then open **Local Ledger**. Use **Take a look around** for the synthetic demo or add your own bank account.

Check manual entry, CSV import/export, Face ID, Shortcuts, and the widget on the phone. Native performance and feature behavior through this signing workflow still need physical-device verification.

## Refresh and update

Free signing expires after seven days. Enable AltStore's **Background Refresh** and allow iOS Background App Refresh. Keep AltServer available on the Mac when you want automatic refreshes. Automatic attempts can fail; check the expiry counter and use **My Apps → Refresh All** before expiration if needed.

Refreshing renews signing without recompiling the application. For a new code version, run the build script again and install the new IPA through AltStore, using the same account and app identity. Export your important records before updating, and keep the existing app installed: deleting Local Ledger deletes its local financial records.

If AltStore expires, its documentation recommends reinstalling AltStore from AltServer without first deleting it. See [AltServer](https://faq.altstore.io/altstore-classic/altserver) and [refresh settings](https://faq.altstore.io/altstore-classic/your-altstore).
