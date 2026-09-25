#!/bin/bash
set -euo pipefail

task_ios_root="$(cd "$(dirname "$0")/.." && pwd)"
task_output_root="$task_ios_root/../outputs/ios"

# Use full Xcode for this build without changing the Mac's global selection.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  task_selected_developer="$(xcode-select -p)"
  if [[ "$task_selected_developer" == */CommandLineTools ]]; then
    if [[ ! -d /Applications/Xcode.app/Contents/Developer ]]; then
      printf '%s\n' 'Install Xcode 26 or later and complete its first-launch setup with iOS support.' >&2
      exit 1
    fi
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

if ! /usr/bin/xcodebuild -checkFirstLaunchStatus || ! /usr/bin/xcodebuild -showsdks >/dev/null; then
  printf '%s\n' 'Open Xcode, review its license, and complete first-launch setup before building.' >&2
  exit 1
fi

/usr/bin/xcrun --sdk iphoneos --show-sdk-path >/dev/null
mkdir -p "$task_output_root"

/usr/bin/xcodebuild \
  -project "$task_ios_root/LocalLedger.xcodeproj" \
  -scheme LocalLedger \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$task_output_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

task_app="$task_output_root/DerivedData/Build/Products/Release-iphoneos/LocalLedger.app"
test -f "$task_app/LocalLedger"
test -f "$task_app/PlugIns/LocalLedgerWidget.appex/LocalLedgerWidget"

task_staging="$(mktemp -d "$task_output_root/.ipa-staging.XXXXXX")"
trap 'rm -rf "$task_staging"' EXIT
mkdir "$task_staging/Payload"
/usr/bin/ditto "$task_app" "$task_staging/Payload/LocalLedger.app"
/usr/bin/ditto -c -k --norsrc --keepParent \
  "$task_staging/Payload" "$task_staging/LocalLedger.ipa"
/usr/bin/unzip -tq "$task_staging/LocalLedger.ipa"
mv "$task_staging/LocalLedger.ipa" "$task_output_root/LocalLedger.ipa"

printf '\nUnsigned Release IPA for AltStore: %s\n' "$task_output_root/LocalLedger.ipa"
printf '%s\n' 'Transfer this IPA to Files on your iPhone, then select it in AltStore > My Apps > +.'
