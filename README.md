# Wealth Buddy

A private money app for UAE residents. It tracks spending and net worth, checks whether you can afford a car or a house, and says how much you can safely save or invest each month.

No account and no personal details. All data stays on the phone, AES-256-GCM encrypted, with the key in the iOS Keychain or Android Keystore.

## Run it

```bash
# 1. Install Flutter (stable): https://docs.flutter.dev/get-started/install
# 2. Generate the Android and iOS folders around this code, and apply the app's settings
./tool/setup.sh
# 3. Check the engines, then start the app on a simulator or phone
flutter test
flutter run
```

`tool/setup.sh` runs `flutter create` for Android and iOS without touching `lib/` or `test/`. It then sets Android `minSdk` to 24 (needed by the secure storage plugin) and turns off Android cloud backup, since the encryption key can't be restored with it.

CI (`.github/workflows/ci.yml`) runs the tests and builds a debug APK and an unsigned iOS build on every push.

## How it's built

```
lib/
  domain/            Pure Dart. No Flutter imports, fully unit-tested.
    models.dart      AppState and its parts (JSON matches the prototype)
    basics.dart      Categories, FX demo rates, money and month formatting
    finance.dart     The shared plan: totals, income, household benchmarks, debt burden,
                     monthly split, projects, suggestions, projections
    recurring.dart   Repeating costs (yearly rent spread monthly) and setup helpers
    parsers.dart     Bank SMS, CSV and statement-line parsing, import classification
  data/
    encrypted_store.dart   One encrypted file; atomic writes; "Delete all data" wipes file and key
  app/state.dart     Riverpod: one controller owns the state, every tab reads Finance from it
  ui/                Welcome, Set up your month, and the five tabs
test/
  parity_test.dart   Dart engines vs results exported from the tested HTML prototype
  fixtures/          Those exported inputs and expected results
  widget_test.dart   Smoke test: first launch and example data
```

Every change goes through `AppController.update`: copy the state, apply the change, expand repeating costs, save, publish. Every screen rebuilds from one `Finance` object, so a new project, transaction or setting updates every tab together.

## Status

Done in this milestone:

- Guided setup: salary, rent (yearly in cheques) or mortgage, and regular costs
- Manual expenses and income, repeating monthly or yearly
- CSV statement import with review, skipped card payments and duplicate detection
- Pasted bank SMS
- Household-aware benchmarks, debt burden, projects with affordability checks and fixes
- Invest tab: grow or safe, emergency fund, projection, suggestions feed

Next:

- **Android SMS capture.** A `BroadcastReceiver` feeding `parseSms`, plus the Play Store `READ_SMS` declaration. iOS doesn't allow reading SMS, so iPhone users rely on statements and manual entry.
- **PDF and Excel statements.** The line parser (`linesToRaw`) is ready and tested. It needs an on-device PDF text extractor that supports passwords.
- **Per-bank templates** for ENBD, ADCB, FAB, ADIB and Mashreq, with the generic parser as the fallback.
- **Live FX and gold prices**, bundled fonts, and cheque-date reminders.

## Numbers to verify before release

- **Benchmark ranges and household weights** are starter estimates. Tune them against UAE household expenditure data.
- **Lending rules** used here: 50% repayment cap, 20% minimum down payment, 48-month car loans. Check them against current Central Bank rules.
- **Scheme details:** unemployment insurance (ILOE) and gratuity rules.
- **Suggestions stay educational.** They describe asset types and never recommend named products; personalised investment advice is licensed in the UAE.
