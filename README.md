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
5. **Get the plan:**
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

### Several projects at once (`lib/domain/plan.dart`)

Every project is planned together with the others by default. Spare money is split in **turns**:

```
Spare AED 8,000 a month                       Oct'26 ─ Feb'27 ─────── Sep'27 ──── Jun'28 ─────────────── Jun'31
Safety cushion first                          ████████
Turn 1 · saving now   Vacation  ~1,250/mo             ███████████████ ✓ on time
                      SUV       ~6,180/mo             ██████████████████████████ ✓ early
Turn 2 · waiting      Home      starts after both                                ███████████████████████ ✓ on time
                                (6,800/mo once the SUV's 1,200 running costs start)
```

1. The credit card, then the safety cushion, come first. Small purchases still save their monthly need during the cushion.
2. Each project's **need** is what's left to save ÷ months left to its date.
3. A turn is the largest group, nearest date first, whose needs fit in spare money and who all make their dates. Each gets its need; leftover goes to the nearest date.
4. Projects that don't fit **wait**; the next turn starts once everyone in this one has saved enough. Waiting is usually free: it still makes its date (the plan screen says so, or says by how much it slips).
5. Each project is bought on its date (or when ready, if late). From then on its loan, running costs, minus any rent it stops, change spare money and the cushion target for everyone after it.

Equal or proportional splits are avoided on purpose: when there isn't enough for everyone, they make everyone late at once.

On the plan screen, **How your spare money is split** shows who's saving now and how much, who waits and why ("Saving for all of them at once needs AED 11,980 a month. You have 8,000"). Two choices:
- **Save for this now too** pins a waiting project into the first turn, after previewing which dates move.
- **Plan this on its own** takes it out (with a warning that the others count on the same money).

Home cards say *Saving now · AED 6,180 a month* or *Waiting · starts Jun 2028*. Payday reminders split the money: "Put AED 1,250 for the vacation and AED 6,180 for the Family SUV today."

### Cost of waiting and the regret check

- **Cost of waiting** (when the verdict is *Later*): the delay is costed line by line in the verdict card. A home counts the rent you keep paying, minus the interest and upkeep you'd pay as an owner, plus the price rising. Trips, weddings, Hajj and education count price rises. A car's running costs make waiting a saving. "Find AED 1,200 more a month" says when that's less than what each month of waiting costs.
- **Regret check** (when the verdict is *Ready now* or *On track*), looking at the month after buying:

  | Check | Passes when |
  |---|---|
  | Cushion still covers you | it covers its months (less half a month) at the new monthly costs |
  | Room to breathe | at least 10% of pay is still spare |
  | Loans comfortable | repayments at or under 35% of pay |
  | Other plans hold | projects planned with it, no earlier than it, keep their dates |

  Two or more warnings make the verdict **Yes, but tight**, with a price that passes every check and a bigger down payment if one helps. One warning keeps the verdict and shows that line under it.

### What if (`lib/domain/whatif.dart`, `lib/ui/whatif_screen.dart`)

**What if…** (on home next to *Your projects*, and on every plan) opens sliders for take-home pay and monthly spending (±30%) and a want-by stepper per project. Every project's ready date, verdict and saving-now/waiting status update on each slider stop; the shared plan is re-run as a whole, so moving one date can move the others.

It also searches for the **smallest change that puts everything on time**: a spending cut or a pay rise, in AED 50 steps. Spending cuts count for more, because they also shrink the cushion needed first (late home example: 2,750 less spending does what 3,050 more pay does). **Try it** sets the slider. Nothing is saved until **Keep these changes**, which lists what will change first.

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
| Price rises (cost of waiting) | Homes, building, renovation 3% a year; trips, weddings, Hajj 4%; education 5% |
| Regret check | Spare after buying ≥ 10% of pay; repayments ≤ 35%; cushion within half a month of its target |
