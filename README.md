# Wealth Buddy

Plan a big purchase: a car, a home, a vacation, a wedding. Answer a few questions and get a plan that says whether you can afford it, by when, and what to do first.

No account and no personal details. Everything stays on the phone, AES-256-GCM encrypted, with the key in the iOS Keychain or Android Keystore.

## How it works

1. **Pick a project:** car, home, build a house, vacation, wedding, education, or something else.
2. **Answer the project questions:** cost, when you want it, and for a car, home or other purchase, savings or a loan (with down payment, rate and term). Homes also ask your current rent.
3. **Answer the money questions:** take-home pay, monthly spending, savings, loan repayments, credit card balance, who relies on your income and how steady it is, and optional investments. These are asked once and reused for every project.
4. **Get the plan:**
   - a verdict: Ready now, On track, Later or Rethink
   - the numbers behind it
   - the steps in order, with dates
   - ways to make it work if it doesn't
   - things to watch out for

### The rules behind the plan (`lib/domain/assess.dart`)

1. **Credit card debt first.** Savings above one month of essentials pay it down now, then spare money each month clears the rest. Card interest is modelled at 3% a month.
2. **Safety cushion next.** Its size depends on your situation:

   | Your situation | Cushion |
   |---|---|
   | Only you rely on your income, fixed salary | 3 months of essentials |
   | Family relies on your income | 6 months |
   | Income varies | 3 months more on top |

   **Small purchases skip this step.** A purchase counts as small when it costs up to one month of take-home pay and is paid from savings. Your savings are still left alone, and the cushion comes after.
3. **Save the upfront amount.** That's the full price, or the down payment plus fees. Savings above the cushion count first.
4. **Buy, then check it still fits:**
   - Loan repayments must stay under the UAE's 50% cap; under 35% counts as comfortable.
   - Monthly costs afterwards must fit your spare money. Car running costs are estimated; a home adds upkeep and subtracts the rent you stop paying.

## Run it

```bash
./tool/setup.sh     # generates the Android and iOS folders, sets minSdk 24, disables Android backup
flutter test        # engine scenarios + smoke test
flutter run
```

CI (`.github/workflows/ci.yml`) runs analyze, tests, an Android debug APK and an unsigned iOS build on every push. It publishes the full output to the `ci-reports` branch.

## Layout

```
lib/
  domain/
    assess.dart      Project kinds, which questions to ask, the decision engine
    models.dart      Money (asked once) and Project
    format.dart      AED formatting and month helpers
  data/encrypted_store.dart
  app/state.dart     Riverpod controller, saves on every change
  ui/
    home_screen.dart    Pick a project, your projects
    wizard_screen.dart  One question per screen
    result_screen.dart  Verdict, numbers, plan, options
test/
  assess_test.dart   Scenarios: no cushion, small purchase, card debt, loan over cap,
                     overspending, ready now, home rent offset, too soon
  widget_test.dart
```

## Numbers to verify before release

| Assumption | Value used |
|---|---|
| Lending | 50% repayment cap; 20% minimum down for cars and expat mortgages; car loans up to 48 months; mortgage fees about 6% |
| Car running costs | 12% of the price a year |
| Home upkeep | 1.5% of the price a year |
| Card interest | 36% a year |
| Small-purchase threshold | One month of take-home pay |
