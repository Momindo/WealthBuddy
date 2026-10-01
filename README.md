# Wealth Buddy

Plan a big purchase: a car, a home, a vacation, a wedding. Answer a few questions and get a plan that says whether you can afford it, by when, and what to do first.

No account and no personal details. Everything stays on the phone, AES-256-GCM encrypted, with the key in the iOS Keychain or Android Keystore.

## How it works

1. **Pick a project:** car, home, build a house, vacation, wedding, education, home renovation, Hajj or Umrah, start a business, new baby, buy gold, phone or laptop, or something else.
2. **Answer the project questions:** cost, when you want it, and for a car, home, renovation or other purchase, savings or a loan (with down payment, rate and term). Rates have quick picks, including a 0% dealer offer for cars, and car loans go up to 5 years. Homes also ask your current rent.
3. **Answer the money questions:** take-home pay, monthly spending, savings, loan repayments, credit card balance, who relies on your income and how steady it is, and optional investments. These are asked once and reused for every project.
4. **Money set aside:** a new project asks whether you've already put money aside for it. Later, **Add money** on any project records a bonus, gift or sale, with a preview of how much sooner it makes the project before you confirm. The money can go to:
   - **The project:** held in its pot.
   - **Your safety cushion:** added to savings.
   - **Your credit card:** pays down the balance; anything beyond it goes to the project.

   If your cushion is short, the sheet shows when putting the money there reaches the same ready date and protects you sooner.
5. **Link it with your other projects:** when you already have a project, a new one asks whether to plan them together and which comes first (default: by the date you want each). See *Linked projects* below.
6. **Get the plan:**
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
3. **Save the upfront amount.** That's the full price, or the down payment plus fees. Money set aside for the project counts first, then savings above the cushion. Set-aside money never skips steps 1 and 2: the plan still says to wait until the card is clear and the cushion is full.
4. **Buy, then check it still fits:**
   - Loan repayments must stay under the UAE's 50% cap; under 35% counts as comfortable.
   - Monthly costs afterwards must fit your spare money. Car running costs are estimated; a home adds upkeep and subtracts the rent you stop paying.

### Linked projects

Spare money can only go to one thing at a time, so linked projects are saved for in turn (`AppData.queue`, `assessChain`):

```
month 0 ─────────── 19 ───────────────────── 54
 SUV:  card → cushion → save   │ buy
 Home:                         │ top up cushion → save down payment │ buy
                               └ spare drops 8,000 → 6,800 (car running costs)
```

- Each project gets all spare money until it's ready; only the last one is paced to its target date.
- Once one is bought, its monthly costs carry into the next: loan instalments, running costs, minus rent it stops. Essentials grow, so the cushion target is recomputed and topped up. Repayment caps count earlier loans.
- Money set aside for a project stays with that project.
- The plan screen lists the order with each ready date, lets you move a project up or down, and suggests a swap when another order gets everything done sooner (for example home first, then SUV: done 6 months sooner because the rent stops).
- A project planned on its own shows a warning that the others count on the same spare money.

## App basics

- **Logo:** steps rising to a gold coin. `lib/ui/logo.dart` draws it as a vector for the app bar and splash, and `tool/make_brand.py` renders the same geometry to the app icon, Android adaptive icon, notification icon and native splash PNGs in `assets/brand/`.
- **First launch:** a three-second splash, then a one-time privacy pop-up: everything stays on this phone, encrypted; no cloud and no account; no ads and no tracking; no name, email or phone number. It's available again from Settings → Privacy.
- **Payday reminders:** the money questions include the day salary arrives. At 3 pm on payday a local notification says what to do with this month's spare money, written from the plan by `lib/domain/reminders.dart`:
  - pay down the card
  - fill the safety cushion
  - put aside X for the project, with the percentage reached
  - or "You can afford the …" once it's ready

  The next three are scheduled on the phone and refreshed on every change. The phone can't see the bank, so messages say what to do rather than claiming anything was saved.
- **Settings:** appearance (system, light or dark), payday reminder on or off and the payday itself, app lock with fingerprint, face or phone PIN, update my money, privacy, delete all data, version.

## Run it

```bash
./tool/setup.sh     # generates Android and iOS folders, applies tool/patch_platforms.py, makes icons and splash
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
| Lending | 50% repayment cap; 20% minimum down for cars and expat mortgages; car loans usually up to 48 months, some banks 60; mortgage fees about 6% |
| Car running costs | 12% of the price a year |
| Home upkeep | 1.5% of the price a year |
| Card interest | 36% a year |
| Small-purchase threshold | One month of take-home pay |
