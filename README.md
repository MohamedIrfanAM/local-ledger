# Local Ledger

[![Android CI](https://github.com/ashr-exe/local-ledger/actions/workflows/android-ci.yml/badge.svg)](https://github.com/ashr-exe/local-ledger/actions/workflows/android-ci.yml)
[![CodeQL](https://github.com/ashr-exe/local-ledger/actions/workflows/codeql.yml/badge.svg)](https://github.com/ashr-exe/local-ledger/actions/workflows/codeql.yml)
[![Android 8+](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)](docs/BUILD.md)
[![Offline](https://img.shields.io/badge/network_permission-none-5C6BC0)](docs/PRIVACY.md)
[![Status: alpha](https://img.shields.io/badge/status-alpha-orange)](docs/LIMITATIONS.md)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

An offline-first Android personal-finance tracker that turns verified Indian bank
SMS alerts into a useful local ledger—without an account, a cloud backend,
analytics, or internet permission.

A native **SwiftUI iOS 26 port** is available in [`ios/`](ios/README.md), with
Liquid Glass controls, the local ledger features, Shortcuts, and widgets. It is a
development preview: iOS uses explicit alert/CSV imports instead of Android's
SMS inbox access. Open `ios/LocalLedger.xcodeproj` in Xcode 26 or later.

> [!IMPORTANT]
> Local Ledger is an early alpha and a convenience tool, not a bank statement or
> an accounting system. SMS delivery and parsing are inherently fallible. Always
> reconcile important decisions against your bank's official records.

## Why it is different

- **Private by construction:** the APK does not request Android's `INTERNET`
  permission. Processing and storage stay on the device.
- **Almost no setup:** select one account per bank, enter its current balance,
  grant SMS access, and start tracking.
- **Event-driven and lightweight:** no polling, foreground service, worker
  scheduler, analytics SDK, ad SDK, ORM, or dependency-injection framework.
- **Defensive ingestion:** a sender must match the bundled bank-specific registry
  before a message is parsed. Duplicate delivery and inbox scanning share one
  fingerprint-based deduplication path.
- **Diagnosable without leaking messages:** a copyable pipeline report records
  only rejection stages and boolean parser signals. It keeps at most 120 events
  for seven days and contains no SMS bodies or financial values.
- **Useful personalisation:** nicknames, categories, inheritable tags, manual
  entries, flexible budgets, filters, local reports, and a modular dashboard.
- **Safe to demo:** hide everything quickly or explore stable synthetic values,
  labels, graphs, transaction/budget drill-downs, and feature previews without
  exposing real ledger content. Demo mode supplies sample data when the ledger is empty.

## What it tracks

Local Ledger currently targets successful digital transactions affecting selected
bank accounts: debits, credits, transfers, reversals, refunds, and similar balance
movements described by supported SMS templates. It extracts the amount,
credit/debit direction, transaction time when present, and a best-effort merchant
label. Full SMS bodies are not retained after parsing.

The bundled static registry currently contains **46 banks and 563 normalized
sender headers**: 562 derived from TRAI's compiled SMS-header workbook dated
16 June 2020 plus one separately marked, reviewed field-observed correction.
Carrier/circle routing prefixes and message-category suffixes are normalized
before matching. Official and observed provenance remain distinct in the asset.

## Install

### From a GitHub release

1. Open the repository's **Releases** page and download the APK and its
   `SHA256SUMS` file.
2. Verify the checksum, then transfer the APK to an Android 8.0+ phone.
3. Allow installation from the chosen file manager and install the APK.
4. Select your banks, enter each current account balance, and tap **Start
   tracking**.
5. Grant `RECEIVE_SMS` and `READ_SMS` when Android asks.

Android and some OEMs restrict sensitive permissions for sideloaded apps. If the
SMS switch is unavailable, open **Settings → Apps → Local Ledger**, use the
three-dot menu to choose **Allow restricted settings**, then return to
**Permissions → SMS**. Labels vary by phone.

Play Protect may also warn about an unverified sideloaded APK using SMS access.
Install only the APK from this repository's signed release, verify
`SHA256SUMS`, and prefer **Install anyway** when offered. If a device leaves no
alternative and you deliberately pause Play Protect scanning, re-enable it
immediately after installation. Google recommends keeping Play Protect enabled.

The latest signed build is on the repository's Releases page. Developers can
also build from source using [the build guide](docs/BUILD.md). Do not install
APKs attached by unknown third parties.

## Everyday use

- New matching bank alerts are processed automatically.
- Open the app to rescan messages received since tracking began.
- Tap a transaction to set its merchant nickname/category and attach payment-only
  or merchant-wide tags. Category tags are inherited too.
- Add cash or other manual entries. Choose whether each entry adjusts the
  selected bank's calculated balance.
- Filter by period, bank, direction, category, merchant, or tag; sort activity by
  date, amount, or merchant.
- Reorder or hide dashboard modules. Included views cover balance drill-down,
  cash flow, daily pace, category mix, Sankey-style money flow, budget status,
  insights, and recent activity.
- Export detailed CSV or formatted PDF reports through Android's local document
  picker. There is no cloud backup.

The app presents 50/30/20 only as an optional starting framework. Budgeting is
personal, so categories and caps remain user-defined.

## Permissions and data boundary

| Permission | Why it is needed |
|---|---|
| `RECEIVE_SMS` | Process new bank alerts when Android delivers them. |
| `READ_SMS` | Recover eligible messages received after tracking began while the app was stopped. |
| `POST_NOTIFICATIONS` | Optional, requested only after creating a budget, for one quiet budget alert per period. |

There is deliberately no internet, contacts, location, phone, call-log, storage,
advertising-ID, or analytics permission. Network permissions are explicitly
removed during manifest merging, CI enforces the source contract, and releases
inspect the final APK. Android backup and device-to-device transfer are disabled
for ledger data. See the full
[privacy model](docs/PRIVACY.md).

## Known limits

The dashboard cannot be 100% authoritative. Banks and carriers may omit, delay,
duplicate, truncate, or change an alert; some transactions are statement-only;
and a parser may misinterpret an unfamiliar template. Credit cards and
activity before setup are outside the current scope. Read the complete
[limitations](docs/LIMITATIONS.md) before relying on totals.

## Project documentation

- [Build and install](docs/BUILD.md)
- [Architecture and design](docs/DESIGN.md)
- [SMS parser support](docs/PARSER_SUPPORT.md)
- [Open-source parser research](docs/PRIOR_ART.md)
- [Privacy and permissions](docs/PRIVACY.md)
- [Limitations](docs/LIMITATIONS.md)
- [Roadmap](docs/ROADMAP.md)
- [Release process](docs/RELEASING.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Development status

Version `0.2.0` is an alpha reliability and product-depth release. Unit tests, Android lint, release builds,
dependency updates, and CodeQL analysis are automated through GitHub Actions.
See [CHANGELOG.md](CHANGELOG.md) for shipped changes and
[the roadmap](docs/ROADMAP.md) for planned work.

## Sender-registry provenance

The checked-in registry is reproducible using
[`tools/extract_trai_registry.py`](tools/extract_trai_registry.py). Its current
source is TRAI's [compiled header workbook published 16 June 2020](https://www.trai.gov.in/node/7411).
The source date is intentionally prominent because the registry can become stale;
updating it without adding a runtime network dependency is a roadmap item.

## License

Licensed under the [Apache License 2.0](LICENSE).
